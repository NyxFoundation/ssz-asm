#include "ssz_asm.h"
#include "hash_declarations.h"

typedef unsigned char U8;
typedef uint64_t U64;
typedef int64_t I64;

extern void *ssz_alloc(ssz_arena *, U64);
extern void *ssz_copy(void *, const void *, U64);

#define BUFFER_SIZE (1UL << 20)
static U8 input[BUFFER_SIZE], wire[BUFFER_SIZE], output[BUFFER_SIZE];
static U8 values[BUFFER_SIZE] __attribute__((aligned(8)));
static U8 decoded_storage[BUFFER_SIZE] __attribute__((aligned(8)));
static U8 scratch_storage[BUFFER_SIZE] __attribute__((aligned(8)));
static U64 test_index;
static U64 assertions;

static I64 syscall3(U64 n, U64 x, void *p, U64 size) {
  register U64 a0 __asm__("a0") = x;
  register void *a1 __asm__("a1") = p;
  register U64 a2 __asm__("a2") = size;
  register U64 a7 __asm__("a7") = n;
  __asm__ volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
  return (I64)a0;
}

static void number(U64 n) {
  char digits[24]; U64 i = 24;
  do { digits[--i] = '0' + n % 10; n /= 10; } while (n);
  syscall3(64, 1, digits + i, 24 - i);
}

__attribute__((noreturn)) static void failure(U64 line) {
  syscall3(64, 1, "FAIL case ", 10); number(test_index);
  syscall3(64, 1, " line ", 6); number(line); syscall3(64, 1, "\n", 1);
  syscall3(93, 1, 0, 0); __builtin_unreachable();
}

#define CHECK(x) do { ++assertions; if (!(x)) failure(__LINE__); } while (0)

static void read_bytes(void *p, U64 n) {
  U8 *dst = p;
  while (n) {
    I64 got = syscall3(63, 0, dst, n);
    CHECK(got > 0 && (U64)got <= n); dst += got; n -= got;
  }
}

static U64 read_word(void) {
  U8 data[8]; read_bytes(data, 8); U64 result = 0;
  for (U64 i = 0; i < 8; ++i) result |= (U64)data[i] << (8*i);
  return result;
}

static int equal(const void *a, const void *b, U64 n) {
  const U8 *x = a, *y = b;
  for (U64 i = 0; i < n; ++i) if (x[i] != y[i]) return 0;
  return 1;
}

typedef struct { U64 kind, payload; } Shape;
static Shape shapes[32768];
static U64 shape_count, shape_cursor;
static const U8 *cursor, *wire_end;

static U64 word(void) {
  CHECK((U64)(wire_end - cursor) >= 8); U64 n = 0;
  for (U64 i = 0; i < 8; ++i) n |= (U64)*cursor++ << (8*i);
  return n;
}

static void parse(ssz_value *value, ssz_arena *a) {
  CHECK(shape_count < 32768);
  U64 kind = word(); value->length = word(); value->selector = word();
  U64 payload = word(); shapes[shape_count++] = (Shape){kind, payload};
  CHECK(payload <= BUFFER_SIZE / (kind ? 24 : 1));
  if (!kind) {
    CHECK((U64)(wire_end - cursor) >= payload);
    value->data = payload ? cursor : 0; cursor += payload; return;
  }
  ssz_value *children = payload ? ssz_alloc(a, payload * 24) : 0;
  CHECK(!payload || children); value->data = children;
  for (U64 i = 0; i < payload; ++i) parse(children + i, a);
}

static void compare(const ssz_value *expected, const ssz_value *actual) {
  CHECK(shape_cursor < shape_count); Shape shape = shapes[shape_cursor++];
  CHECK(actual->length == expected->length && actual->selector == expected->selector);
  if (!shape.payload) { CHECK(actual->data == 0); return; }
  CHECK((uintptr_t)actual->data >= (uintptr_t)decoded_storage);
  CHECK((uintptr_t)actual->data < (uintptr_t)decoded_storage + BUFFER_SIZE);
  U64 span = shape.payload * (shape.kind ? 24 : 1);
  CHECK((uintptr_t)actual->data + span <= (uintptr_t)decoded_storage + BUFFER_SIZE);
  if (!shape.kind) { CHECK(equal(expected->data, actual->data, shape.payload)); return; }
  const ssz_value *x = expected->data, *y = actual->data;
  for (U64 i = 0; i < shape.payload; ++i) compare(x + i, y + i);
}

static void public_abi(const Operations *ops, const ssz_value *value, U64 budget) {
  register U64 r0 __asm__("s0") = 101, r1 __asm__("s1") = 102;
  register U64 r2 __asm__("s2") = 103, r3 __asm__("s3") = 104;
  register U64 r4 __asm__("s4") = 105, r5 __asm__("s5") = 106;
  register U64 r6 __asm__("s6") = 107, r7 __asm__("s7") = 108;
  register U64 r8 __asm__("s8") = 109, r9 __asm__("s9") = 110;
  register U64 r10 __asm__("s10") = 111, r11 __asm__("s11") = 112;
  ssz_arena scratch = {scratch_storage, budget}; U8 root[32];
  __asm__ volatile("" : "+r"(r0), "+r"(r1), "+r"(r2), "+r"(r3),
    "+r"(r4), "+r"(r5), "+r"(r6), "+r"(r7), "+r"(r8), "+r"(r9),
    "+r"(r10), "+r"(r11) : : "memory");
  CHECK(ops->hash(value, root, &scratch) == 0);
  __asm__ volatile("" : "+r"(r0), "+r"(r1), "+r"(r2), "+r"(r3),
    "+r"(r4), "+r"(r5), "+r"(r6), "+r"(r7), "+r"(r8), "+r"(r9),
    "+r"(r10), "+r"(r11) : : "memory");
  CHECK(r0 == 101 && r1 == 102 && r2 == 103 && r3 == 104);
  CHECK(r4 == 105 && r5 == 106 && r6 == 107 && r7 == 108);
  CHECK(r8 == 109 && r9 == 110 && r10 == 111 && r11 == 112);
}

static void regular(const Operations *ops, const ssz_value *value, U64 len,
    const U8 *expected_root, U64 scratch_size) {
  U8 root[33]; ssz_value decoded;
  ssz_arena scratch = {scratch_storage, scratch_size};
  CHECK(ops->encode(value, output, BUFFER_SIZE) == (I64)len);
  CHECK(equal(output, input, len));
  if (len) CHECK(ops->encode(value, output, len - 1) == -2);
  CHECK(ops->hash(value, root + 1, &scratch) == 0);
  CHECK(equal(root + 1, expected_root, 32));
  CHECK(scratch.next == scratch_storage && scratch.remaining == scratch_size);
  ssz_arena arena = {decoded_storage, BUFFER_SIZE};
  CHECK(ops->decode(input, len, &decoded, &arena) == 0);
  shape_cursor = 0; compare(value, &decoded); CHECK(shape_cursor == shape_count);
  CHECK(ops->hash(&decoded, root + 1, &scratch) == 0);
  CHECK(equal(root + 1, expected_root, 32));
  CHECK(ops->encode(&decoded, output, BUFFER_SIZE) == (I64)len);
  CHECK(equal(output, input, len));
  public_abi(ops, value, scratch_size);
}

static void execute(void) {
  U64 index = read_word(), mode = read_word(), len = read_word();
  U64 wire_len = read_word(), budget = read_word();
  CHECK(index < OPERATION_COUNT && len <= BUFFER_SIZE && wire_len <= BUFFER_SIZE);
  CHECK(budget <= BUFFER_SIZE);
  read_bytes(wire, wire_len); read_bytes(input, len);
  U8 expected_root[32]; read_bytes(expected_root, 32);
  const Operations *ops = operations + index;
  ssz_value value, decoded; ssz_arena arena = {decoded_storage, budget};
  if (mode == 1) { CHECK(ops->decode(input, len, &decoded, &arena) < 0); return; }
  if (mode == 3) { CHECK(ops->decode(input, len, &decoded, &arena) == -2); return; }
  ssz_arena construction = {values, BUFFER_SIZE};
  cursor = wire; wire_end = wire + wire_len; shape_count = 0; parse(&value, &construction);
  CHECK(cursor == wire_end);
  if (mode == 0) { regular(ops, &value, len, expected_root, budget); return; }
  ssz_arena scratch = {scratch_storage, budget}; U8 root[32];
  if (mode == 2) CHECK(ops->hash(&value, root, &scratch) == -2);
  if (mode == 4) {
    CHECK(ops->hash(&value, root, &scratch) == -1);
    CHECK(ops->encode(&value, output, BUFFER_SIZE) == -1);
  }
  CHECK(scratch.next == scratch_storage && scratch.remaining == budget);
}

static int run(void) {
  U64 count = read_word();
  for (test_index = 0; test_index < count; ++test_index) execute();
  number(count); syscall3(64, 1, " differential cases, ", 21);
  number(assertions); syscall3(64, 1, " checks passed\n", 15);
  return 0;
}

void _start(void) {
  U64 result = run(); syscall3(93, result, 0, 0); __builtin_unreachable();
}
