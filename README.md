# Installation
```
nimble install https://github.com/tim-st/nim-lzma
```

# Usage

You will need the `liblzma` library installed on your system. If you're on Windows, download the file `liblzma.dll` from [here](https://tukaani.org/xz/).

```nim
import lzma

var s = "uncompressed data"
doAssert s.compress.decompress == s
```