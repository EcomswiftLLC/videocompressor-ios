// In-process FFmpeg (LGPL build) wrapper for Shrinkly. No command line, no shell: libav* calls only.
#include "ShrinkFF.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <errno.h>

#include "libavutil/avutil.h"
#include "libavutil/opt.h"
#include "libavutil/display.h"
#include "libavutil/channel_layout.h"
#include "libavutil/pixdesc.h"
#include "libavutil/imgutils.h"
#include "libavcodec/avcodec.h"
#include "libavformat/avformat.h"
#include "libavfilter/avfilter.h"
#include "libavfilter/buffersrc.h"
#include "libavfilter/buffersink.h"
#include "libswscale/swscale.h"

static void set_error(char *dst, int len, const char *prefix, int averr) {
    if (!dst || len <= 0) return;
    char buf[128] = {0};
    if (averr < 0) av_strerror(averr, buf, sizeof(buf));
    snprintf(dst, (size_t)len, "%s%s%s", prefix ? prefix : "", (prefix && buf[0]) ? ": " : "", buf);
}

const char *shk_license(void) { return avformat_license(); }
const char *shk_configuration(void) { return avformat_configuration(); }
int shk_has_encoder(const char *name) { return avcodec_find_encoder_by_name(name) != NULL; }
int shk_has_decoder(const char *name) { return avcodec_find_decoder_by_name(name) != NULL; }
void shk_free(void *p) { free(p); }

static int display_rotation(const AVStream *st) {
    const AVPacketSideData *sd = av_packet_side_data_get(st->codecpar->coded_side_data, st->codecpar->nb_coded_side_data, AV_PKT_DATA_DISPLAYMATRIX);
    if (!sd || sd->size < 9 * 4) return 0;
    double theta = -av_display_rotation_get((const int32_t *)sd->data);
    int rot = (int)lround(theta);
    rot %= 360;
    if (rot < 0) rot += 360;
    return rot;
}

static double stream_duration(AVFormatContext *fmt, AVStream *vs) {
    if (fmt->duration != AV_NOPTS_VALUE && fmt->duration > 0) return (double)fmt->duration / AV_TIME_BASE;
    if (vs->duration != AV_NOPTS_VALUE && vs->duration > 0) return (double)vs->duration * av_q2d(vs->time_base);
    return 0;
}

// MARK: probe

int shk_probe(const char *path, ShkProbe *out) {
    memset(out, 0, sizeof(*out));
    AVFormatContext *fmt = NULL;
    int ret = avformat_open_input(&fmt, path, NULL, NULL);
    if (ret < 0) { set_error(out->error, sizeof(out->error), "Cannot open file", ret); return ret; }
    ret = avformat_find_stream_info(fmt, NULL);
    if (ret < 0) { set_error(out->error, sizeof(out->error), "Cannot read streams", ret); avformat_close_input(&fmt); return ret; }
    int vi = av_find_best_stream(fmt, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    if (vi < 0) { snprintf(out->error, sizeof(out->error), "No video stream"); avformat_close_input(&fmt); return -1; }
    AVStream *vs = fmt->streams[vi];
    AVCodecParameters *cp = vs->codecpar;
    int rot = display_rotation(vs);
    out->width = (rot == 90 || rot == 270) ? cp->height : cp->width;
    out->height = (rot == 90 || rot == 270) ? cp->width : cp->height;
    out->duration = stream_duration(fmt, vs);
    AVRational fr = av_guess_frame_rate(fmt, vs, NULL);
    out->fps = fr.num > 0 && fr.den > 0 ? av_q2d(fr) : 30.0;
    snprintf(out->video_codec, sizeof(out->video_codec), "%s", avcodec_get_name(cp->codec_id));
    int ai = av_find_best_stream(fmt, AVMEDIA_TYPE_AUDIO, -1, vi, NULL, 0);
    out->has_audio = ai >= 0;
    if (ai >= 0) out->audio_bitrate = fmt->streams[ai]->codecpar->bit_rate;
    out->video_bitrate = cp->bit_rate;
    if (out->video_bitrate <= 0 && fmt->bit_rate > 0) out->video_bitrate = fmt->bit_rate - (out->audio_bitrate > 0 ? out->audio_bitrate : 0);
    out->is_hdr = cp->color_trc == AVCOL_TRC_SMPTE2084 || cp->color_trc == AVCOL_TRC_ARIB_STD_B67;
    out->ok = out->width > 0 && out->height > 0;
    if (!out->ok) snprintf(out->error, sizeof(out->error), "Video has no size");
    avformat_close_input(&fmt);
    return out->ok ? 0 : -1;
}

// MARK: thumbnail

static int open_video_decoder(const char *path, AVFormatContext **fmt, AVCodecContext **dec, int *vi) {
    int ret = avformat_open_input(fmt, path, NULL, NULL);
    if (ret < 0) return ret;
    if ((ret = avformat_find_stream_info(*fmt, NULL)) < 0) return ret;
    *vi = av_find_best_stream(*fmt, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    if (*vi < 0) return -1;
    AVStream *vs = (*fmt)->streams[*vi];
    const AVCodec *codec = vs->codecpar->codec_id == AV_CODEC_ID_AV1 ? avcodec_find_decoder_by_name("libdav1d") : NULL;
    if (!codec) codec = avcodec_find_decoder(vs->codecpar->codec_id);
    if (!codec) return -1;
    *dec = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(*dec, vs->codecpar);
    (*dec)->thread_count = 0;
    return avcodec_open2(*dec, codec, NULL);
}

int shk_thumbnail(const char *path, double seconds, int max_dim, uint8_t **rgba, int *width, int *height) {
    *rgba = NULL;
    AVFormatContext *fmt = NULL;
    AVCodecContext *dec = NULL;
    AVPacket *pkt = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    struct SwsContext *sws = NULL;
    int ret = -1;
    int got = 0;
    // Pass 0 seeks near the requested time. Pass 1 reopens the file and reads from the start up to that time (some
    // containers, MPEG-TS for one, seek to a spot with no decodable picture). Pass 2 takes the first picture.
    for (int pass = 0; pass < 3 && !got; pass++) {
        avcodec_free_context(&dec);
        avformat_close_input(&fmt);
        int vi = -1;
        if ((ret = open_video_decoder(path, &fmt, &dec, &vi)) < 0) goto done;
        AVStream *vs = fmt->streams[vi];
        int64_t base = fmt->start_time != AV_NOPTS_VALUE ? fmt->start_time : 0;
        int64_t target = av_rescale_q(base + (int64_t)(seconds * AV_TIME_BASE), AV_TIME_BASE_Q, vs->time_base);
        if (pass == 0 && seconds > 0.05) av_seek_frame(fmt, -1, base + (int64_t)(seconds * AV_TIME_BASE), AVSEEK_FLAG_BACKWARD);
        int need_target = seconds > 0.05 && pass < 2;
        int guard = 0;
        int eof = 0;
        while (!got && !eof && guard++ < 6000) {
            int rr = av_read_frame(fmt, pkt);
            if (rr < 0) {
                eof = 1;
                avcodec_send_packet(dec, NULL);
            } else if (pkt->stream_index != vi) {
                av_packet_unref(pkt);
                continue;
            } else {
                int sent = avcodec_send_packet(dec, pkt);
                av_packet_unref(pkt);
                if (sent < 0) continue;
            }
            while (avcodec_receive_frame(dec, frame) >= 0) {
                if (need_target && frame->best_effort_timestamp != AV_NOPTS_VALUE && frame->best_effort_timestamp < target) { av_frame_unref(frame); continue; }
                got = 1;
                break;
            }
        }
    }
    if (!got) { ret = -1; goto done; }
    int sw = frame->width, sh = frame->height;
    double scale = (double)max_dim / (double)(sw > sh ? sw : sh);
    if (scale > 1) scale = 1;
    int ow = (int)(sw * scale), oh = (int)(sh * scale);
    if (ow < 2) ow = 2;
    if (oh < 2) oh = 2;
    sws = sws_getContext(sw, sh, (enum AVPixelFormat)frame->format, ow, oh, AV_PIX_FMT_RGBA, SWS_BICUBIC, NULL, NULL, NULL);
    if (!sws) { ret = -1; goto done; }
    uint8_t *buf = (uint8_t *)malloc((size_t)ow * (size_t)oh * 4);
    if (!buf) { ret = -1; goto done; }
    uint8_t *dst[4] = {buf, NULL, NULL, NULL};
    int dstride[4] = {ow * 4, 0, 0, 0};
    sws_scale(sws, (const uint8_t *const *)frame->data, frame->linesize, 0, sh, dst, dstride);
    *rgba = buf; *width = ow; *height = oh;
    ret = 0;
done:
    sws_freeContext(sws);
    av_frame_free(&frame);
    av_packet_free(&pkt);
    avcodec_free_context(&dec);
    avformat_close_input(&fmt);
    return ret;
}

// MARK: transcode

typedef struct {
    AVFormatContext *ifmt, *ofmt;
    AVCodecContext *vdec, *venc, *adec, *aenc;
    AVFilterGraph *vgraph, *agraph;
    AVFilterContext *vsrc, *vsink, *asrc, *asink;
    AVStream *vin, *ain, *vout, *aout;
    int vidx, aidx;
    int64_t base;            // start time of the file in AV_TIME_BASE units
    double trim_start, trim_end, span;
    int64_t v_offset, a_offset; // trim start in stream time base
    int video_done, audio_done;
    int64_t last_audio_pts;
    ShkProgress progress;
    void *context;
    double last_reported;
    volatile int *cancel;
} Job;

static int open_decoder(AVStream *st, AVCodecContext **out) {
    const AVCodec *dec = NULL;
    if (st->codecpar->codec_id == AV_CODEC_ID_AV1) dec = avcodec_find_decoder_by_name("libdav1d");
    if (!dec) dec = avcodec_find_decoder(st->codecpar->codec_id);
    if (!dec) return AVERROR_DECODER_NOT_FOUND;
    AVCodecContext *ctx = avcodec_alloc_context3(dec);
    if (!ctx) return AVERROR(ENOMEM);
    int ret = avcodec_parameters_to_context(ctx, st->codecpar);
    if (ret < 0) { avcodec_free_context(&ctx); return ret; }
    ctx->pkt_timebase = st->time_base;
    ctx->thread_count = 0;
    ret = avcodec_open2(ctx, dec, NULL);
    if (ret < 0) { avcodec_free_context(&ctx); return ret; }
    *out = ctx;
    return 0;
}

static int write_packets(AVCodecContext *enc, AVStream *ost, AVFormatContext *ofmt, AVFrame *frame) {
    int ret = avcodec_send_frame(enc, frame);
    if (ret < 0 && ret != AVERROR_EOF) return ret;
    AVPacket *pkt = av_packet_alloc();
    while (1) {
        ret = avcodec_receive_packet(enc, pkt);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) { ret = 0; break; }
        if (ret < 0) break;
        av_packet_rescale_ts(pkt, enc->time_base, ost->time_base);
        pkt->stream_index = ost->index;
        ret = av_interleaved_write_frame(ofmt, pkt);
        if (ret < 0) break;
    }
    av_packet_free(&pkt);
    return ret;
}

static void report(Job *j, double seconds) {
    if (!j->progress || j->span <= 0) return;
    double f = seconds / j->span;
    if (f < 0) f = 0;
    if (f > 0.999) f = 0.999;
    if (f - j->last_reported >= 0.004) { j->last_reported = f; j->progress(f, j->context); }
}

static int build_video_graph(Job *j, const ShkParams *p, int rotation, AVRational out_fps) {
    char args[512], chain[512];
    j->vgraph = avfilter_graph_alloc();
    AVRational tb = j->vin->time_base;
    AVRational sar = j->vdec->sample_aspect_ratio.num > 0 ? j->vdec->sample_aspect_ratio : (AVRational){1, 1};
    snprintf(args, sizeof(args), "video_size=%dx%d:pix_fmt=%d:time_base=%d/%d:pixel_aspect=%d/%d",
             j->vdec->width, j->vdec->height, j->vdec->pix_fmt, tb.num, tb.den, sar.num, sar.den);
    int ret = avfilter_graph_create_filter(&j->vsrc, avfilter_get_by_name("buffer"), "in", args, NULL, j->vgraph);
    if (ret < 0) return ret;
    ret = avfilter_graph_create_filter(&j->vsink, avfilter_get_by_name("buffersink"), "out", NULL, NULL, j->vgraph);
    if (ret < 0) return ret;
    enum AVPixelFormat fmts[] = {AV_PIX_FMT_NV12, AV_PIX_FMT_NONE};
    ret = av_opt_set_int_list(j->vsink, "pix_fmts", fmts, AV_PIX_FMT_NONE, AV_OPT_SEARCH_CHILDREN);
    if (ret < 0) return ret;

    const char *rot = "";
    if (rotation == 90) rot = "transpose=clock,";
    else if (rotation == 180) rot = "hflip,vflip,";
    else if (rotation == 270) rot = "transpose=cclock,";
    snprintf(chain, sizeof(chain), "%sfps=fps=%d/%d,scale=%d:%d:flags=bicubic,setsar=1", rot, out_fps.num, out_fps.den, p->width, p->height);

    AVFilterInOut *outputs = avfilter_inout_alloc();
    AVFilterInOut *inputs = avfilter_inout_alloc();
    outputs->name = av_strdup("in"); outputs->filter_ctx = j->vsrc; outputs->pad_idx = 0; outputs->next = NULL;
    inputs->name = av_strdup("out"); inputs->filter_ctx = j->vsink; inputs->pad_idx = 0; inputs->next = NULL;
    ret = avfilter_graph_parse_ptr(j->vgraph, chain, &inputs, &outputs, NULL);
    avfilter_inout_free(&inputs);
    avfilter_inout_free(&outputs);
    if (ret < 0) return ret;
    return avfilter_graph_config(j->vgraph, NULL);
}

static int build_audio_graph(Job *j, int sample_rate, int mono) {
    char args[512], layout[64], chain[256];
    j->agraph = avfilter_graph_alloc();
    if (j->adec->ch_layout.order == AV_CHANNEL_ORDER_UNSPEC) av_channel_layout_default(&j->adec->ch_layout, j->adec->ch_layout.nb_channels > 0 ? j->adec->ch_layout.nb_channels : 2);
    av_channel_layout_describe(&j->adec->ch_layout, layout, sizeof(layout));
    snprintf(args, sizeof(args), "time_base=1/%d:sample_rate=%d:sample_fmt=%s:channel_layout=%s",
             j->adec->sample_rate, j->adec->sample_rate, av_get_sample_fmt_name(j->adec->sample_fmt), layout);
    int ret = avfilter_graph_create_filter(&j->asrc, avfilter_get_by_name("abuffer"), "ain", args, NULL, j->agraph);
    if (ret < 0) return ret;
    ret = avfilter_graph_create_filter(&j->asink, avfilter_get_by_name("abuffersink"), "aout", NULL, NULL, j->agraph);
    if (ret < 0) return ret;
    snprintf(chain, sizeof(chain), "aformat=sample_fmts=fltp:sample_rates=%d:channel_layouts=%s", sample_rate, mono ? "mono" : "stereo");
    AVFilterInOut *outputs = avfilter_inout_alloc();
    AVFilterInOut *inputs = avfilter_inout_alloc();
    outputs->name = av_strdup("in"); outputs->filter_ctx = j->asrc; outputs->pad_idx = 0; outputs->next = NULL;
    inputs->name = av_strdup("out"); inputs->filter_ctx = j->asink; inputs->pad_idx = 0; inputs->next = NULL;
    ret = avfilter_graph_parse_ptr(j->agraph, chain, &inputs, &outputs, NULL);
    avfilter_inout_free(&inputs);
    avfilter_inout_free(&outputs);
    if (ret < 0) return ret;
    return avfilter_graph_config(j->agraph, NULL);
}

static int drain_video_filter(Job *j, AVFrame *filt) {
    while (1) {
        int ret = av_buffersink_get_frame(j->vsink, filt);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) return 0;
        if (ret < 0) return ret;
        filt->pict_type = AV_PICTURE_TYPE_NONE;
        double t = filt->pts * av_q2d(av_buffersink_get_time_base(j->vsink));
        report(j, t);
        ret = write_packets(j->venc, j->vout, j->ofmt, filt);
        av_frame_unref(filt);
        if (ret < 0) return ret;
    }
}

static int drain_audio_filter(Job *j, AVFrame *filt) {
    while (1) {
        int ret = av_buffersink_get_frame(j->asink, filt);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) return 0;
        if (ret < 0) return ret;
        ret = write_packets(j->aenc, j->aout, j->ofmt, filt);
        av_frame_unref(filt);
        if (ret < 0) return ret;
    }
}

static int handle_video_frame(Job *j, AVFrame *frame, AVFrame *filt) {
    int64_t pts = frame->best_effort_timestamp;
    if (pts == AV_NOPTS_VALUE) { av_frame_unref(frame); return 0; }
    double t = pts * av_q2d(j->vin->time_base) - (double)j->base / AV_TIME_BASE;
    if (t + 1e-4 < j->trim_start) { av_frame_unref(frame); return 0; }
    if (j->trim_end > 0 && t > j->trim_end) { j->video_done = 1; av_frame_unref(frame); return 0; }
    frame->pts = pts - j->v_offset;
    int ret = av_buffersrc_add_frame_flags(j->vsrc, frame, AV_BUFFERSRC_FLAG_KEEP_REF);
    av_frame_unref(frame);
    if (ret < 0) return ret;
    return drain_video_filter(j, filt);
}

static int handle_audio_frame(Job *j, AVFrame *frame, AVFrame *filt) {
    int64_t pts = frame->pts;
    if (pts == AV_NOPTS_VALUE) pts = frame->best_effort_timestamp;
    if (pts == AV_NOPTS_VALUE) { av_frame_unref(frame); return 0; }
    double t = pts * av_q2d(j->ain->time_base) - (double)j->base / AV_TIME_BASE;
    if (t + 1e-4 < j->trim_start) { av_frame_unref(frame); return 0; }
    if (j->trim_end > 0 && t > j->trim_end) { j->audio_done = 1; av_frame_unref(frame); return 0; }
    frame->pts = av_rescale_q(pts - j->a_offset, j->ain->time_base, (AVRational){1, j->adec->sample_rate});
    int ret = av_buffersrc_add_frame_flags(j->asrc, frame, AV_BUFFERSRC_FLAG_KEEP_REF);
    av_frame_unref(frame);
    if (ret < 0) return ret;
    return drain_audio_filter(j, filt);
}

static int decode_packet(Job *j, AVCodecContext *dec, AVPacket *pkt, AVFrame *frame, AVFrame *filt, int is_video) {
    int ret = avcodec_send_packet(dec, pkt);
    if (ret < 0 && ret != AVERROR(EAGAIN) && ret != AVERROR_EOF) return 0; // a bad packet is skipped, not fatal
    while (1) {
        ret = avcodec_receive_frame(dec, frame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) return 0;
        if (ret < 0) return 0;
        ret = is_video ? handle_video_frame(j, frame, filt) : handle_audio_frame(j, frame, filt);
        if (ret < 0) return ret;
    }
}

int shk_transcode(const ShkParams *p, ShkProgress progress, void *context, volatile int *cancel, char *error, int error_length) {
    Job J;
    memset(&J, 0, sizeof(J));
    J.progress = progress;
    J.context = context;
    J.cancel = cancel;
    J.vidx = J.aidx = -1;
    J.trim_start = p->trim_start > 0 ? p->trim_start : 0;
    J.trim_end = p->trim_end > 0 ? p->trim_end : 0;
    J.last_reported = -1;
    AVPacket *pkt = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    AVFrame *filt = av_frame_alloc();
    AVDictionary *opts = NULL;
    int ret = 0;
    int header_written = 0;
    int cancelled = 0;

    if ((ret = avformat_open_input(&J.ifmt, p->input, NULL, NULL)) < 0) { set_error(error, error_length, "Cannot open the video", ret); goto end; }
    if ((ret = avformat_find_stream_info(J.ifmt, NULL)) < 0) { set_error(error, error_length, "Cannot read the video", ret); goto end; }
    J.vidx = av_find_best_stream(J.ifmt, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    if (J.vidx < 0) { ret = J.vidx; set_error(error, error_length, "This file has no video", ret); goto end; }
    J.vin = J.ifmt->streams[J.vidx];
    if (p->audio_bitrate > 0) {
        J.aidx = av_find_best_stream(J.ifmt, AVMEDIA_TYPE_AUDIO, -1, J.vidx, NULL, 0);
        if (J.aidx >= 0) J.ain = J.ifmt->streams[J.aidx];
    }
    J.base = J.ifmt->start_time != AV_NOPTS_VALUE ? J.ifmt->start_time : 0;
    double total = stream_duration(J.ifmt, J.vin);
    double end = J.trim_end > 0 ? J.trim_end : total;
    J.span = end - J.trim_start;
    if (J.span <= 0) J.span = total > 0 ? total : 1;
    J.v_offset = av_rescale_q(J.base + (int64_t)(J.trim_start * AV_TIME_BASE), AV_TIME_BASE_Q, J.vin->time_base);
    if (J.ain) J.a_offset = av_rescale_q(J.base + (int64_t)(J.trim_start * AV_TIME_BASE), AV_TIME_BASE_Q, J.ain->time_base);

    if ((ret = open_decoder(J.vin, &J.vdec)) < 0) { set_error(error, error_length, "This video format can't be decoded", ret); goto end; }
    if (J.ain && open_decoder(J.ain, &J.adec) < 0) { J.ain = NULL; J.aidx = -1; }

    // output
    if ((ret = avformat_alloc_output_context2(&J.ofmt, NULL, "mp4", p->output)) < 0) { set_error(error, error_length, "Cannot create the output", ret); goto end; }
    AVRational out_fps = av_d2q(p->fps > 1 ? p->fps : 30, 60 * 1001);
    int rotation = display_rotation(J.vin);
    if ((ret = build_video_graph(&J, p, rotation, out_fps)) < 0) { set_error(error, error_length, "Cannot prepare the picture", ret); goto end; }

    const AVCodec *venc = avcodec_find_encoder_by_name(p->hevc ? "hevc_videotoolbox" : "h264_videotoolbox");
    if (!venc) { ret = AVERROR_ENCODER_NOT_FOUND; set_error(error, error_length, "The hardware video encoder is not available", ret); goto end; }
    J.venc = avcodec_alloc_context3(venc);
    J.venc->width = p->width;
    J.venc->height = p->height;
    J.venc->pix_fmt = AV_PIX_FMT_NV12;
    J.venc->time_base = av_buffersink_get_time_base(J.vsink);
    J.venc->framerate = out_fps;
    J.venc->bit_rate = p->video_bitrate;
    J.venc->gop_size = (int)lround(av_q2d(out_fps)) * 2;
    J.venc->sample_aspect_ratio = (AVRational){1, 1};
    if (J.ofmt->oformat->flags & AVFMT_GLOBALHEADER) J.venc->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    av_opt_set(J.venc->priv_data, "profile", p->hevc ? "main" : "high", 0);
    av_opt_set(J.venc->priv_data, "allow_sw", "0", 0);
    if ((ret = avcodec_open2(J.venc, venc, NULL)) < 0) { set_error(error, error_length, "The video encoder could not start", ret); goto end; }
    J.vout = avformat_new_stream(J.ofmt, NULL);
    if (!J.vout) { ret = AVERROR(ENOMEM); goto end; }
    avcodec_parameters_from_context(J.vout->codecpar, J.venc);
    J.vout->time_base = J.venc->time_base;
    J.vout->avg_frame_rate = out_fps;
    if (p->hevc) J.vout->codecpar->codec_tag = MKTAG('h', 'v', 'c', '1');

    if (J.adec) {
        int sr = J.adec->sample_rate > 46000 ? 48000 : 44100;
        int mono = J.adec->ch_layout.nb_channels == 1;
        if ((ret = build_audio_graph(&J, sr, mono)) < 0) { set_error(error, error_length, "Cannot prepare the sound", ret); goto end; }
        const AVCodec *aenc = avcodec_find_encoder_by_name("aac");
        if (!aenc) { ret = AVERROR_ENCODER_NOT_FOUND; goto end; }
        J.aenc = avcodec_alloc_context3(aenc);
        J.aenc->sample_rate = sr;
        av_channel_layout_default(&J.aenc->ch_layout, mono ? 1 : 2);
        J.aenc->sample_fmt = AV_SAMPLE_FMT_FLTP;
        J.aenc->time_base = (AVRational){1, sr};
        int64_t abr = p->audio_bitrate;
        if (mono && abr > 96000) abr = 96000;
        J.aenc->bit_rate = abr;
        if (J.ofmt->oformat->flags & AVFMT_GLOBALHEADER) J.aenc->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
        if ((ret = avcodec_open2(J.aenc, aenc, NULL)) < 0) { set_error(error, error_length, "The audio encoder could not start", ret); goto end; }
        av_buffersink_set_frame_size(J.asink, J.aenc->frame_size);
        J.aout = avformat_new_stream(J.ofmt, NULL);
        if (!J.aout) { ret = AVERROR(ENOMEM); goto end; }
        avcodec_parameters_from_context(J.aout->codecpar, J.aenc);
        J.aout->time_base = J.aenc->time_base;
    }
    if (!p->strip_metadata) av_dict_copy(&J.ofmt->metadata, J.ifmt->metadata, 0);

    if (!(J.ofmt->oformat->flags & AVFMT_NOFILE)) {
        if ((ret = avio_open(&J.ofmt->pb, p->output, AVIO_FLAG_WRITE)) < 0) { set_error(error, error_length, "Cannot write the output file", ret); goto end; }
    }
    av_dict_set(&opts, "movflags", "+faststart", 0);
    if ((ret = avformat_write_header(J.ofmt, &opts)) < 0) { set_error(error, error_length, "Cannot start the output file", ret); goto end; }
    header_written = 1;

    if (J.trim_start > 0.05) av_seek_frame(J.ifmt, -1, J.base + (int64_t)(J.trim_start * AV_TIME_BASE), AVSEEK_FLAG_BACKWARD);

    // main loop
    while (1) {
        if (cancel && *cancel) { cancelled = 1; break; }
        ret = av_read_frame(J.ifmt, pkt);
        if (ret < 0) { ret = 0; break; }
        if (pkt->stream_index == J.vidx) {
            ret = decode_packet(&J, J.vdec, pkt, frame, filt, 1);
        } else if (J.ain && pkt->stream_index == J.aidx) {
            ret = decode_packet(&J, J.adec, pkt, frame, filt, 0);
        }
        av_packet_unref(pkt);
        if (ret < 0) { set_error(error, error_length, "The video could not be processed", ret); goto end; }
        if (J.video_done && (!J.ain || J.audio_done)) break;
    }
    if (cancelled) goto end;

    // flush
    avcodec_send_packet(J.vdec, NULL);
    while (avcodec_receive_frame(J.vdec, frame) >= 0) { if ((ret = handle_video_frame(&J, frame, filt)) < 0) break; }
    ret = 0;
    av_buffersrc_add_frame_flags(J.vsrc, NULL, 0);
    if ((ret = drain_video_filter(&J, filt)) < 0) { set_error(error, error_length, "Finishing the picture failed", ret); goto end; }
    if ((ret = write_packets(J.venc, J.vout, J.ofmt, NULL)) < 0) { set_error(error, error_length, "Finishing the video failed", ret); goto end; }
    if (J.adec) {
        avcodec_send_packet(J.adec, NULL);
        while (avcodec_receive_frame(J.adec, frame) >= 0) { if ((ret = handle_audio_frame(&J, frame, filt)) < 0) break; }
        av_buffersrc_add_frame_flags(J.asrc, NULL, 0);
        drain_audio_filter(&J, filt);
        write_packets(J.aenc, J.aout, J.ofmt, NULL);
    }
    ret = av_write_trailer(J.ofmt);
    header_written = 0;
    if (ret < 0) { set_error(error, error_length, "Finishing the file failed", ret); goto end; }
    if (progress) progress(1.0, context);

end:
    if (J.ofmt && header_written) av_write_trailer(J.ofmt);
    if (J.ofmt && !(J.ofmt->oformat->flags & AVFMT_NOFILE) && J.ofmt->pb) avio_closep(&J.ofmt->pb);
    av_dict_free(&opts);
    avfilter_graph_free(&J.vgraph);
    avfilter_graph_free(&J.agraph);
    avcodec_free_context(&J.vdec);
    avcodec_free_context(&J.adec);
    avcodec_free_context(&J.venc);
    avcodec_free_context(&J.aenc);
    if (J.ofmt) avformat_free_context(J.ofmt);
    avformat_close_input(&J.ifmt);
    av_packet_free(&pkt);
    av_frame_free(&frame);
    av_frame_free(&filt);
    if (cancelled) return 1;
    return ret < 0 ? ret : 0;
}
