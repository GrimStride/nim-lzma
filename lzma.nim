when defined(windows):
  const liblzma = "liblzma.dll" # you can download the windows binary from: https://tukaani.org/xz/
elif defined(macosx):
  const liblzma = "liblzma.dylib"
else:
  const liblzma = "liblzma.so"

type
  lzma_ret {.size: sizeof(int).} = enum
    LZMA_OK = 0
    LZMA_STREAM_END = 1
    LZMA_NO_CHECK = 2
    LZMA_UNSUPPORTED_CHECK = 3
    LZMA_GET_CHECK = 4
    LZMA_MEM_ERROR = 5
    LZMA_MEMLIMIT_ERROR = 6
    LZMA_FORMAT_ERROR = 7
    LZMA_OPTIONS_ERROR = 8
    LZMA_DATA_ERROR = 9
    LZMA_BUF_ERROR = 10
    LZMA_PROG_ERROR = 11
  lzma_check {.size: sizeof(int).} = enum
    LZMA_CHECK_NONE = 0
    LZMA_CHECK_CRC32 = 1
    LZMA_CHECK_CRC64 = 4
    LZMA_CHECK_SHA256 = 10
  lzma_action  {.size: sizeof(int).} = enum
    LZMA_RUN = 0
    LZMA_SYNC_FLUSH = 1
    LZMA_FULL_FLUSH = 2
    LZMA_FINISH = 3
    LZMA_FULL_BARRIER = 4
  lzma_mode  {.size: sizeof(int).} = enum
    LZMA_MODE_FAST = 1
    LZMA_MODE_NORMAL = 2
  lzma_match_finder  {.size: sizeof(int).} = enum
    LZMA_MF_HC3 = 3
    LZMA_MF_HC4 = 4
    LZMA_MF_BT2 = 18
    LZMA_MF_BT3 = 19
    LZMA_MF_BT4 = 20
  lzma_stream {.bycopy.} = object
    next_in: ptr uint8
    avail_in: csize
    total_in: uint64
    next_out: ptr uint8
    avail_out: csize
    total_out: uint64
    allocator: pointer
    internal: pointer
    reserved_ptr1: pointer
    reserved_ptr2: pointer
    reserved_ptr3: pointer
    reserved_ptr4: pointer
    reserved_int1: uint64
    reserved_int2: uint64
    reserved_int3: csize
    reserved_int4: csize
    reserved_enum1: int
    reserved_enum2: int
  lzma_options_lzma = object
    dict_size: uint32
    preset_dic: uint8
    preset_dic_size: uint32
    lc: uint32
    lp: uint32
    pb: uint32
    mode: int32
    nice_len: uint32
    mf: int32
    depth: uint32
    reserved_int1: uint32
    reserved_int2: uint32
    reserved_int3: uint32 
    reserved_int4: uint32
    reserved_int5: uint32
    reserved_int6: uint32
    reserved_int7: uint32
    reserved_int8: uint32
    reserved_enum1: int
    reserved_enum2: int
    reserved_enum3: int
    reserved_enum4: int
    reserved_ptr1: pointer
    reserved_ptr2: pointer
  lzma_vli = uint64
  lzma_filter = object
    id: lzma_vli
    options: pointer
  lzma_options_easy = object
    filters: lzma_filter
    opt_lzma: lzma_options_lzma

{.push dynlib: liblzma, cdecl, importc.}
proc lzma_stream_buffer_bound(uncompressed_size: csize): csize
proc lzma_alone_encoder(strm: ptr lzma_stream, options: ptr lzma_options_lzma): lzma_ret
proc lzma_stream_buffer_encode(filter: ptr lzma_filter, check: lzma_check, allocator: pointer, `in`: ptr uint8,
    in_size: csize, `out`: ptr uint8, out_pos: ptr csize, out_size: csize): lzma_ret
proc lzma_easy_buffer_encode(preset: uint32, check: lzma_check, allocator: pointer, `in`: ptr uint8,
    in_size: csize, `out`: ptr uint8, out_pos: ptr csize, out_size: csize): lzma_ret
proc lzma_code(strm: ptr lzma_stream, action: lzma_action): lzma_ret
proc lzma_end(strm: ptr lzma_stream)
proc lzma_auto_decoder(strm: ptr lzma_stream, memlimit: uint64, flags: uint32): lzma_ret
{.pop.}

const
  memoryLimit1gb*: uint64 = 1 shl 30
  memoryLimit2gb*: uint64 = memoryLimit1gb * 2
  memoryLimit4gb*: uint64 = memoryLimit2gb * 2
  memoryLimit8gb*: uint64 = memoryLimit4gb * 2
  memoryLimit16gb*: uint64 = memoryLimit8gb * 2
  LZMA_CONCATENATED: uint32 = 0x00000008
  LZMA_FILTER_1 = 4611686018427387905'u64
  LZMA_FILTER_2: uint64 = 33

type LzmaError* = object of Exception

proc compress*(input: seq[uint8]): seq[uint8] =
  if unlikely(input.len == 0):
    return
  result = newSeqUninitialized[uint8](max(2 shl 12, input.len*2))
  var available = result.len
  var resultUsed = 0
  var s: lzma_stream
  var opt: lzma_options_lzma
  opt.dict_size = 8388608'u32
  opt.preset_dic = 2'u8
  opt.preset_dic_size = 0'u32
  opt.lc = 3'u32
  opt.lp = 0'u32
  opt.pb = 2'u32
  opt.mode = 2.int32
  opt.nice_len = 128'u32
  opt.mf = 20.int32
  opt.depth = 0'u32
  let r = lzma_alone_encoder(addr(s), addr(opt))
  if unlikely(r != LZMA_OK):
    raise newException(LzmaError, "Creating stream failed: " & $r)
  s.next_in = unsafeAddr(input[0])
  s.avail_in = len(input)
  s.next_out = addr(result[0])
  s.avail_out = available
  while true:
    let r = lzma_code(addr(s), if s.avail_in == 0: LZMA_FINISH else: LZMA_RUN)
    if r == LZMA_STREAM_END:
      inc(resultUsed, available - s.avail_out)
      if unlikely(s.avail_in != 0):
        raise newException(LzmaError, "Stream at end but not all input data decompressed.")
      result.setLen(resultUsed)
      lzma_end(addr(s))
      break
    if unlikely(r != LZMA_OK):
      raise newException(LzmaError, "Stream not at end and an error occured: " & $r)
    if s.avail_out == 0:
      inc(resultUsed, available - s.avail_out)
      result.setLen(result.len * 2)
      s.next_out = addr(result[resultUsed]) 
      available = result.len - resultUsed
      s.avail_out = available

proc compress*(input: seq[char]): seq[char] =
  result = cast[seq[char]](compress(cast[seq[uint8]](input)))

proc compress*(input: string): string =
  result = cast[string](compress(cast[seq[uint8]](input)))


proc strmcompress*(input: seq[uint8]): seq[uint8] =
  if unlikely(input.len == 0):
    return
  let worstLength = lzma_stream_buffer_bound(input.len)
  result = newSeqUninitialized[uint8](worstLength)
  var actualSize = 0
  var filt: lzma_filter
  filt.id = LZMA_FILTER_1
  filt.options = nil
  let r = lzma_stream_buffer_encode(
    addr(filt),
    LZMA_CHECK_NONE,
    nil,
    unsafeAddr(input[0]),
    len(input),
    addr(result[0]),
    addr(actualSize),
    worstLength
  )
  if unlikely(r != LZMA_OK):
    raise newException(LzmaError, "Compressing input failed: " & $r)
  result.setLen(actualSize)

proc strmcompress*(input: seq[char]): seq[char] =
  result = cast[seq[char]](strmcompress(cast[seq[uint8]](input)))

proc strmcompress*(input: string): string =
  result = cast[string](strmcompress(cast[seq[uint8]](input)))


proc xzcompress*(input: seq[uint8], compressionLevel = 9): seq[uint8] =
  if unlikely(compressionLevel notin 0..9):
    raise newException(ValueError, "Compression level must be in 0..9")
  if unlikely(input.len == 0):
    return
  let worstLength = lzma_stream_buffer_bound(input.len)
  result = newSeqUninitialized[uint8](worstLength)
  var actualSize = 0
  let r = lzma_easy_buffer_encode(
    compressionLevel.uint32,
    LZMA_CHECK_CRC64,
    nil,
    unsafeAddr(input[0]),
    len(input),
    addr(result[0]),
    addr(actualSize),
    worstLength
  )
  if unlikely(r != LZMA_OK):
    raise newException(LzmaError, "Compressing input failed: " & $r)
  result.setLen(actualSize)

proc xzcompress*(input: seq[char], compressionLevel = 9): seq[char] =
  result = cast[seq[char]](xzcompress(cast[seq[uint8]](input), compressionLevel))

proc xzcompress*(input: string, compressionLevel = 9): string =
  result = cast[string](xzcompress(cast[seq[uint8]](input), compressionLevel))

proc decompress*(input: seq[uint8], memLimit: static[uint64]): seq[uint8] =
  if unlikely(input.len == 0):
    return
  result = newSeqUninitialized[uint8](max(2 shl 12, input.len*2))
  var available = result.len
  var resultUsed = 0
  var s: lzma_stream
  let r = lzma_auto_decoder(addr(s), memLimit, LZMA_CONCATENATED)
  if unlikely(r != LZMA_OK):
    raise newException(LzmaError, "Creating stream failed: " & $r)
  s.next_in = unsafeAddr(input[0])
  s.avail_in = len(input)
  s.next_out = addr(result[0])
  s.avail_out = available
  while true:
    let r = lzma_code(addr(s), if s.avail_in == 0: LZMA_FINISH else: LZMA_RUN)
    if r == LZMA_STREAM_END:
      inc(resultUsed, available - s.avail_out)
      if unlikely(s.avail_in != 0):
        raise newException(LzmaError, "Stream at end but not all input data decompressed.")
      result.setLen(resultUsed)
      lzma_end(addr(s))
      break
    if unlikely(r != LZMA_OK):
      raise newException(LzmaError, "Stream not at end and an error occured: " & $r)
    if s.avail_out == 0:
      inc(resultUsed, available - s.avail_out)
      result.setLen(result.len * 2)
      s.next_out = addr(result[resultUsed]) 
      available = result.len - resultUsed
      s.avail_out = available

proc decompress*(input: seq[uint8]): seq[uint8] =
  result = decompress(input, memoryLimit1gb)

proc decompress*(input: seq[char], memLimit: static[uint64]): seq[char] =
  result = cast[seq[char]](decompress(cast[seq[uint8]](input)))

proc decompress*(input: seq[char]): seq[char] =
  result = decompress(input, memoryLimit1gb)

proc decompress*(input: string, memLimit: static[uint64]): string =
  result = cast[string](decompress(cast[seq[uint8]](input), memLimit))

proc decompress*(input: string): string =
  result = decompress(input, memoryLimit1gb)


when isMainModule:
  import unittest
  import random

  suite "LZMA Exceptions":

    test "ValueError: invalid compression level":
      expect ValueError:
        discard xzcompress("abc", 10)
      expect ValueError:
        discard xzcompress("abc", -1)

    test "LzmaError: Decompressing uncompressed data":
      expect LzmaError:
        discard decompress("abc")

    test "LzmaError: memory limit reached":
      expect LzmaError:
        discard decompress(xzcompress("abc"), 256)

  suite "LZMA: string":

    const emptyStr = ""
    const oneCharStr = "x"
    const smallStr = "abc"

    randomize()
    const strLen = 100_000
    var longStr = newStringOfCap(strLen)
    for x in 1..strLen:
      longStr.add(char(rand(30)))

    for compressionLevel in 0..9:
      test "compression: level " & $compressionLevel & "/9":
        check(emptyStr.xzcompress(compressionLevel).decompress == emptyStr)
        check(oneCharStr.xzcompress(compressionLevel).decompress == oneCharStr)
        check(smallStr.xzcompress(compressionLevel).decompress == smallStr)
        check(longStr.xzcompress(compressionLevel).decompress == longStr)

  suite "LZMA: seq[uint8] / seq[byte]":

    const emptySeq: seq[uint8] = @[]
    const oneElementSeq = @[uint8(100)]
    const smallSeq = @[uint8(0), uint8(99), uint8(255)]

    randomize()
    const seqLen = 100_000
    var longSeq = newSeqOfCap[uint8](seqLen)
    for x in 1..seqLen:
      longSeq.add(uint8(rand(30)))

    for compressionLevel in 0..9:
      test "compression: level " & $compressionLevel & "/9":
        check(emptySeq.xzcompress(compressionLevel).decompress == emptySeq)
        check(oneElementSeq.xzcompress(compressionLevel).decompress == oneElementSeq)
        check(smallSeq.xzcompress(compressionLevel).decompress == smallSeq)
        check(longSeq.xzcompress(compressionLevel).decompress == longSeq)

  suite "LZMA: seq[char]":

    const emptySeq: seq[char] = @[]
    const oneElementSeq = @[char(100)]
    const smallSeq = @[char(0), char(99), char(255)]

    randomize()
    const seqLen = 100_000
    var longSeq = newSeqOfCap[char](seqLen)
    for x in 1..seqLen:
      longSeq.add(char(rand(30)))

    for compressionLevel in 0..9:
      test "compression: level " & $compressionLevel & "/9":
        check(emptySeq.xzcompress(compressionLevel).decompress == emptySeq)
        check(oneElementSeq.xzcompress(compressionLevel).decompress == oneElementSeq)
        check(smallSeq.xzcompress(compressionLevel).decompress == smallSeq)
        check(longSeq.xzcompress(compressionLevel).decompress == longSeq)
