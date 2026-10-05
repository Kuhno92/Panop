// A stand-in for libdovi (Dolby Vision RPU parsing), with the part of its C interface that AetherEngine uses.
// SPDX-License-Identifier: MIT
//
// Why it exists: the real library ships as a static xcframework with a module map, and so does LumeEngine's FFmpeg.
// Xcode puts both module maps at the same path ("Multiple commands produce .../include/module.modulemap"), so the
// two engines could not be built into one app. This package takes the place of `LibDovi` (same name, same product),
// and what it does is nothing: every parse fails, so Dolby Vision profile 7 is not converted to 8.1 and plays as its
// HDR10 base layer, which is what a player without libdovi does. Profiles 5 and 8 are not affected.

#ifndef DOVI_H
#define DOVI_H

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>

typedef struct DoviRpuOpaque DoviRpuOpaque;

typedef struct {
    /**
     * Pointer to the data buffer
     */
    const uint8_t *data;
    /**
     * Data buffer size
     */
    size_t len;
} DoviData;

typedef struct {
    /**
     * Profile guessed from the values in the header
     */
    uint8_t guessed_profile;
    /**
     * Enhancement layer type (FEL or MEL) if the RPU is profile 7
     * null pointer if not profile 7
     */
    const char *el_type;
    /**
     * Deprecated since 3.2.0
     * The field is not actually part of the RPU header
     */
    uint8_t rpu_nal_prefix;
    uint8_t rpu_type;
    uint16_t rpu_format;
    uint8_t vdr_rpu_profile;
    uint8_t vdr_rpu_level;
    bool vdr_seq_info_present_flag;
    bool chroma_resampling_explicit_filter_flag;
    uint8_t coefficient_data_type;
    uint64_t coefficient_log2_denom;
    uint8_t vdr_rpu_normalized_idc;
    bool bl_video_full_range_flag;
    uint64_t bl_bit_depth_minus8;
    uint64_t el_bit_depth_minus8;
    uint64_t vdr_bit_depth_minus8;
    bool spatial_resampling_filter_flag;
    uint8_t reserved_zero_3bits;
    bool el_spatial_resampling_filter_flag;
    bool disable_residual_flag;
    bool vdr_dm_metadata_present_flag;
    bool use_prev_vdr_rpu_flag;
    uint64_t prev_vdr_rpu_id;
} DoviRpuDataHeader;

DoviRpuOpaque *dovi_parse_unspec62_nalu(const uint8_t *buf, size_t len);
void dovi_rpu_free(DoviRpuOpaque *ptr);
void dovi_data_free(const DoviData *data);
const DoviData *dovi_write_unspec62_nalu(DoviRpuOpaque *ptr);
int32_t dovi_convert_rpu_with_mode(DoviRpuOpaque *ptr, uint8_t mode);
const DoviRpuDataHeader *dovi_rpu_get_header(const DoviRpuOpaque *ptr);
void dovi_rpu_free_header(const DoviRpuDataHeader *ptr);

#endif
