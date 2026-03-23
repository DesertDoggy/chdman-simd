# Licenses — CHDMAN_SIMD

## Patched files (MAME)

The patches modify original files from the MAME project (https://github.com/mamedev/mame).

| File | Original authors | License |
|---|---|---|
| `src/tools/chdman.cpp` | Aaron Giles | BSD-3-Clause |
| `src/lib/util/hashing.cpp` | Aaron Giles, Vas Crabb | BSD-3-Clause |
| `src/osd/modules/file/winfile.cpp` | Aaron Giles, Vas Crabb | BSD-3-Clause |

Modifications contributed by CHDMAN_SIMD are also released under **BSD-3-Clause**.

BSD-3-Clause summary:
> Redistribution and use in source and binary forms, with or without modification,
> are permitted provided that the following conditions are met:
> 1. Redistributions of source code must retain the above copyright notice.
> 2. Redistributions in binary form must reproduce the above copyright notice.
> 3. Neither the name of the copyright holder nor the names of its contributors
>    may be used to endorse or promote products derived from this software.

## LZMA SDK (LzmaDecOpt.asm)

- Author: Igor Pavlov
- License: **Public domain** (explicit declaration since 2008 in `lzma/C/7zTypes.h`)
- Source: https://www.7-zip.org/sdk.html

## zlib-ng

- Authors: Hans Kristian Rosbach and contributors
- License: **zlib** (permissive, BSD-compatible)
- Source: https://github.com/zlib-ng/zlib-ng

## GitHub publishing verdict

✅ **Publishing on GitHub is permitted** for the patches and the standalone build under BSD-3-Clause.

Requirements:
- Keep the `// license:BSD-3-Clause` and `// copyright-holders:` headers in all modified files.
- Credit MAME in the README (origin of patched sources).
- Do not use the "MAME" name to endorse or promote a derived product without permission.
