#include "message.h"

_Static_assert(sizeof(ssz_value) == 24, "The generated library uses LP64 values");
_Static_assert(sizeof(ssz_arena) == 16, "The generated library uses LP64 arenas");

static uint8_t arena_storage[8192] __attribute__((aligned(8)));
static uint8_t scratch_storage[8192] __attribute__((aligned(8)));

int example(void) {
    const uint8_t id[8] = {42};
    const uint8_t payload[3] = {0xaa, 0xbb, 0xcc};
    const ssz_value fields[] = {{id, 8, 0}, {payload, 3, 0}};
    const ssz_value message = {fields, 2, 0};
    uint8_t encoded[15], original_root[32], decoded_root[32];
    ssz_value decoded;
    ssz_arena arena = {arena_storage, sizeof(arena_storage)};
    ssz_arena scratch = {scratch_storage, sizeof(scratch_storage)};

    if (Message_serialize(&message, encoded, sizeof(encoded)) != 15) return 1;
    if (encoded[0] != 42 || encoded[8] != 12 || encoded[12] != 0xaa) return 2;
    if (Message_deserialize(encoded, sizeof(encoded), &decoded, &arena) != 0) return 3;
    if (Message_hash_tree_root(&message, original_root, &scratch) != 0) return 4;
    scratch = (ssz_arena){scratch_storage, sizeof(scratch_storage)};
    if (Message_hash_tree_root(&decoded, decoded_root, &scratch) != 0) return 5;
    for (unsigned i = 0; i < 32; ++i)
        if (original_root[i] != decoded_root[i]) return 6;
    return 0;
}
