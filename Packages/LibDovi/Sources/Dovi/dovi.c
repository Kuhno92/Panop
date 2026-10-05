// SPDX-License-Identifier: MIT
// See include/dovi.h: nothing is parsed, so a Dolby Vision RPU is left as it is.

#include "dovi.h"

DoviRpuOpaque *dovi_parse_unspec62_nalu(const uint8_t *buf, size_t len) {
    (void)buf;
    (void)len;
    return NULL;
}

void dovi_rpu_free(DoviRpuOpaque *ptr) {
    (void)ptr;
}

void dovi_data_free(const DoviData *data) {
    (void)data;
}

const DoviData *dovi_write_unspec62_nalu(DoviRpuOpaque *ptr) {
    (void)ptr;
    return NULL;
}

int32_t dovi_convert_rpu_with_mode(DoviRpuOpaque *ptr, uint8_t mode) {
    (void)ptr;
    (void)mode;
    return -1;
}

const DoviRpuDataHeader *dovi_rpu_get_header(const DoviRpuOpaque *ptr) {
    (void)ptr;
    return NULL;
}

void dovi_rpu_free_header(const DoviRpuDataHeader *ptr) {
    (void)ptr;
}
