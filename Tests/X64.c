#include <stdint.h>
#include "Abi.h"
#include "Platform.h"

#define CHECK(condition) do { if (!(condition)) return __LINE__; } while (0)
#define WORD(value) ((uint64_t)(int64_t)(int32_t)(uint32_t)(value))
#define BINARY_OPS(M) \
  M(add, a + b) M(sub, a - b) M(mul, a * b) \
  M(divu, b ? a / b : UINT64_MAX) M(remu, b ? a % b : a) \
  M(sltu, a < b) M(slt, (int64_t)a < (int64_t)b) \
  M(sll, a << (b & 63)) M(srl, a >> (b & 63)) M(sra, (uint64_t)((int64_t)a >> (b & 63))) \
  M(and, a & b) M(or, a | b) M(xor, a ^ b) M(addw, WORD(a + b)) M(subw, WORD(a - b))
#define UNARY_OPS(M) \
  M(addi, a - 1) M(andi, a) M(ori, UINT64_MAX) M(xori, ~a) \
  M(slti, (int64_t)a < -1) M(sltiu, a < UINT64_MAX) M(addiw, WORD(a - 1)) \
  M(slli, a << 63) M(srli, a >> 63) M(srai, (uint64_t)((int64_t)a >> 63)) \
  M(slliw, WORD(a << 31)) M(srliw, WORD((uint32_t)a >> 1))
#define BRANCHES(M) \
  M(eq, a == b) M(ne, a != b) M(lt, (int64_t)a < (int64_t)b) \
  M(ge, (int64_t)a >= (int64_t)b) M(ltu, a < b) M(geu, a >= b)
#define DECLARE_BINARY(name, expression) extern uint64_t op_##name(uint64_t, uint64_t);
#define DECLARE_UNARY(name, expression) extern uint64_t op_##name(uint64_t);
#define DECLARE_BRANCH(name, expression) extern uint64_t branch_##name(uint64_t, uint64_t);
BINARY_OPS(DECLARE_BINARY)
UNARY_OPS(DECLARE_UNARY)
BRANCHES(DECLARE_BRANCH)

extern uint64_t alignment(void), constants(void), nested(uint64_t, uint64_t);
extern uint64_t call_six(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
extern uint64_t op_ld(const void *), op_lw(const void *), op_lwu(const void *);
extern uint64_t op_lh(const void *), op_lhu(const void *), op_lb(const void *), op_lbu(const void *);
extern void op_sd(void *, uint64_t), op_sw(void *, uint64_t), op_sh(void *, uint64_t), op_sb(void *, uint64_t);

static int arithmetic(uint64_t a, uint64_t b) {
#define CHECK_BINARY(name, expression) CHECK(op_##name(a, b) == (uint64_t)(expression));
#define CHECK_UNARY(name, expression) CHECK(op_##name(a) == (uint64_t)(expression));
#define CHECK_BRANCH(name, expression) CHECK(branch_##name(a, b) == (uint64_t)(expression));
  BINARY_OPS(CHECK_BINARY)
  UNARY_OPS(CHECK_UNARY)
  BRANCHES(CHECK_BRANCH)
  return 0;
}

static int memory(void) {
  uint8_t bytes[] = {0x55, 0x98, 0xba, 0xdc, 0xfe, 0xff, 0xff, 0xff, 0xff, 0xaa};
  CHECK(op_ld(bytes) == UINT64_C(0xfffffffffedcba98));
  CHECK(op_lw(bytes) == UINT64_C(0xfffffffffedcba98));
  CHECK(op_lwu(bytes) == UINT64_C(0xfedcba98));
  CHECK(op_lh(bytes) == UINT64_C(0xffffffffffffba98));
  CHECK(op_lhu(bytes) == UINT64_C(0xba98));
  CHECK(op_lb(bytes) == UINT64_C(0xffffffffffffff98));
  CHECK(op_lbu(bytes) == 0x98);
  void (*stores[])(void *, uint64_t) = {op_sb, op_sh, op_sw, op_sd};
  for (unsigned width = 0; width < 4; ++width) {
    for (unsigned i = 1; i < 9; ++i) bytes[i] = 0;
    stores[width](bytes, UINT64_C(0x8877665544332211));
    for (unsigned i = 0; i < 8; ++i)
      CHECK(bytes[i + 1] == (i < (1u << width) ? (i + 1) * 0x11 : 0));
    CHECK(bytes[0] == 0x55 && bytes[9] == 0xaa);
  }
  return 0;
}

static int frames(void) {
  ABI_SEED();
  ABI_BARRIER();
  CHECK(alignment() == 0);
  CHECK(nested(40, 2) == 42);
  CHECK(call_six(1, 2, 3, 4, 5, 6) == 21);
  CHECK(constants() == 0xfedcba98);
  ABI_BARRIER();
  CHECK(ABI_INTACT);
  return 0;
}

int test_main(void) {
  const uint64_t values[] = {0, 1, 31, 32, 63, 64, 65, UINT64_MAX,
    UINT64_C(0x8000000000000000), UINT64_C(0x80000000), UINT64_C(0xffffffff),
    UINT64_C(0xdeadbeef98765432)};
  for (unsigned i = 0; i < sizeof(values) / sizeof(values[0]); ++i) {
    for (unsigned j = 0; j < sizeof(values) / sizeof(values[0]); ++j) {
      int result = arithmetic(values[i], values[j]);
      if (result) return result;
    }
  }
  int result = memory();
  if (result) return result;
  result = frames();
  if (result) return result;
  const char message[] = "x86-64 scalar, frame, alignment, and ABI checks passed\n";
  syscall3(SYS_WRITE, 1, message, sizeof(message) - 1);
  return 0;
}
