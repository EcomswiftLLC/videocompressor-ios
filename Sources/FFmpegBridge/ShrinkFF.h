#ifndef SHRINKFF_H
#define SHRINKFF_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Facts about a file, read with libavformat.
typedef struct {
    int ok;
    double duration;
    int width;
    int height;
    double fps;
    char video_codec[32];
    int has_audio;
    int64_t video_bitrate;
    int64_t audio_bitrate;
    int is_hdr;
    char error[256];
} ShkProbe;

/// Returns 0 on success. On failure `out->error` explains why.
int shk_probe(const char *path, ShkProbe *out);

typedef struct {
    const char *input;
    const char *output;
    /// Output size as the person sees it (rotation already applied). Both even.
    int width;
    int height;
    double fps;
    int64_t video_bitrate;
    /// 0 = drop the audio.
    int64_t audio_bitrate;
    /// 0 = H.264, 1 = HEVC (both hardware encoders from VideoToolbox).
    int hevc;
    /// Seconds. trim_end <= 0 means to the end.
    double trim_start;
    double trim_end;
    int strip_metadata;
} ShkParams;

typedef void (*ShkProgress)(double fraction, void *context);

/// Transcodes to MP4 (H.264 or HEVC + AAC). Returns 0 on success, 1 when cancelled, a negative number on error.
/// Set `*cancel` to non-zero from another thread to stop.
int shk_transcode(const ShkParams *params, ShkProgress progress, void *context, volatile int *cancel, char *error, int error_length);

/// One frame as RGBA, scaled to fit `max_dim`. Free with shk_free. Returns 0 on success.
int shk_thumbnail(const char *path, double seconds, int max_dim, uint8_t **rgba, int *width, int *height);

void shk_free(void *pointer);

/// Library versions and licence line for the About screen and tests.
const char *shk_license(void);
const char *shk_configuration(void);
int shk_has_encoder(const char *name);
int shk_has_decoder(const char *name);

#ifdef __cplusplus
}
#endif

#endif
