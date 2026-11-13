#ifndef SSZ_ASM_H
#define SSZ_ASM_H

#include <stdint.h>

typedef struct {
    const void *data;
    uint64_t length;
    uint64_t selector;
} ssz_value;

typedef struct {
    uint8_t *next;
    uint64_t remaining;
} ssz_arena;

enum {
    SSZ_INVALID = -1,
    SSZ_NO_SPACE = -2,
    SSZ_OVERFLOW = -3
};

#define SSZ_DECLARE(name) \
    int64_t name##_serialize(const ssz_value *, uint8_t *, uint64_t); \
    int64_t name##_deserialize(const uint8_t *, uint64_t, ssz_value *, ssz_arena *); \
    int64_t name##_hash_tree_root(const ssz_value *, uint8_t [32], ssz_arena *)

#endif
