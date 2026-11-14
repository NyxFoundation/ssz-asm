#include <stdint.h>
#include "Abi.h"
#include "hash_runtime_vectors.h"

extern void ssz_sha256_pair(uint8_t *, const uint8_t *);
extern void ssz_merkleize(uint8_t *, uint8_t *, uint64_t, uint64_t);
extern void ssz_merkleize_progressive(uint8_t *, uint8_t *, uint64_t);

static const uint8_t zero_digest[32] = {
  0xf5,0xa5,0xfd,0x42,0xd1,0x6a,0x20,0x30,0x27,0x98,0xef,0x6e,0xd3,0x09,0x97,0x9b,
  0x43,0x00,0x3d,0x23,0x20,0xd9,0xf0,0xe8,0xea,0x98,0x31,0xa9,0x27,0x59,0xfb,0x4b
};

static const uint8_t range_digest[32] = {
  0xfd,0xea,0xb9,0xac,0xf3,0x71,0x03,0x62,0xbd,0x26,0x58,0xcd,0xc9,0xa2,0x9e,0x8f,
  0x9c,0x75,0x7f,0xcf,0x98,0x11,0x60,0x3a,0x8c,0x44,0x7c,0xd1,0xd9,0x15,0x11,0x08
};

static int equal(const uint8_t *a, const uint8_t *b) {
  for (unsigned i = 0; i < 32; ++i) if (a[i] != b[i]) return 0;
  return 1;
}

static int known_answers(void) {
  uint8_t input[65], output[33];
  for (unsigned i = 0; i < 65; ++i) input[i] = 0;
  ssz_sha256_pair(output + 1, input + 1);
  if (!equal(output + 1, zero_digest)) return 1;
  for (unsigned i = 0; i < 64; ++i) input[i + 1] = i;
  ssz_sha256_pair(output + 1, input + 1);
  if (!equal(output + 1, range_digest)) return 2;
  ssz_sha256_pair(input + 1, input + 1);
  if (!equal(input + 1, range_digest)) return 3;
  return 0;
}

static int merkle(void) {
  uint8_t chunks[86 * 32], root[32];
  for (unsigned test = 0; test < MERKLE_CASES; ++test) {
    for (unsigned i = 0; i < sizeof(chunks); ++i) chunks[i] = (i * 17 + i / 13) & 255;
    if (merkle_depths[test] < 0)
      ssz_merkleize_progressive(root, chunks, merkle_counts[test]);
    else ssz_merkleize(root, chunks, merkle_counts[test], merkle_depths[test]);
    if (!equal(root, merkle_roots[test])) return 10 + test;
  }
  return 0;
}

static int abi(void) {
  ABI_SEED();
  uint8_t input[64], out[32];
  for (unsigned i = 0; i < 64; ++i) input[i] = i;
  ABI_BARRIER();
  ssz_sha256_pair(out, input);
  ssz_merkleize(out, input, 2, 7);
  ssz_merkleize_progressive(out, input, 2);
  ABI_BARRIER();
  return ABI_INTACT ? 0 : 100;
}

int test_main(void) {
  int result = known_answers();
  if (result) return result;
  result = merkle();
  return result ? result : abi();
}
