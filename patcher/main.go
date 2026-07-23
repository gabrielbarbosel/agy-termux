// patch rewrites the Antigravity CLI ARM64 binary so it runs on Android/Termux.
//
// Two classes of in-place fix, applied to a copy of the official binary:
//   - TCMalloc for a 39-bit virtual address space: the bundled Google allocator
//     tags pointers at bit 42 and masks addresses at 48 bits, both beyond
//     Android ARM64's 39-bit VA. The tag/mask instructions and inlined constants
//     are rewritten down to bit 35 / 39 bits. These are absent (counts zero) on
//     builds Google already fixed upstream.
//   - faccessat2 -> faccessat: the syscall number 439, which some Android seccomp
//     policies kill with SIGSYS, is rewritten to 48 (faccessat), which they allow.
//
// It is a byte-for-byte reimplementation of the previous Python patcher.
//
// Usage: patch <src> <dst>
package main

import (
	"bytes"
	"debug/elf"
	"encoding/binary"
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: patch <src> <dst>")
		os.Exit(2)
	}
	if err := patch(os.Args[1], os.Args[2]); err != nil {
		fmt.Fprintln(os.Stderr, "patch:", err)
		os.Exit(1)
	}
}

// patch reads src, applies every rewrite in place, and writes the result to dst.
func patch(src, dst string) error {
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	lo, hi := allocatorRange(data)
	tcmalloc := patchTCMalloc(data, lo, hi)
	faccessat := patchFaccessat2(data)
	if err := os.WriteFile(dst, data, 0o755); err != nil {
		return err
	}
	fmt.Printf("tcmalloc: %d rewrites  faccessat2: %d rewrites\n", tcmalloc, faccessat)
	return nil
}

// word and putWord read and write a little-endian 32-bit ARM64 instruction word.
func word(data []byte, off int) uint32     { return binary.LittleEndian.Uint32(data[off:]) }
func putWord(data []byte, off int, w uint32) { binary.LittleEndian.PutUint32(data[off:], w) }

// allocatorRange returns the file-offset range of the google_malloc section,
// where TCMalloc's tagging code lives, or the whole binary when that section is
// absent — matching the original patcher's fallback.
func allocatorRange(data []byte) (lo, hi int) {
	f, err := elf.NewFile(bytes.NewReader(data))
	if err != nil {
		return 0, len(data)
	}
	defer f.Close()
	if s := f.Section("google_malloc"); s != nil {
		return int(s.Offset), int(s.Offset + s.Size)
	}
	return 0, len(data)
}

// tagConstants maps each inlined bit-42 TCMalloc tag constant / dealloc mask to
// its bit-35 (39-bit-VA) replacement.
var tagConstants = map[uint32]uint32{
	0xD2C20009: 0xD2C00409,
	0xD2C2000A: 0xD2C0040A,
	0xF2C20008: 0xF2DFF408,
	0xF2C20009: 0xF2DFF409,
	0xD2C10009: 0xD2C00209,
	0xD2C1000A: 0xD2C0020A,
	0xF2C38008: 0xF2DFF708,
	0xF2C38009: 0xF2DFF709,
	0x92560A6C: 0x925D0A6C,
	0x92560A6A: 0x925D0A6A,
	0xD2C3000D: 0xD2C0060D,
	0xD2C3000C: 0xD2C0060C,
	0xD2C08008: 0xD2C00108,
}

// patchTCMalloc applies the four allocator rewrites over the google_malloc range,
// in the original order, and returns the total number of words changed.
func patchTCMalloc(data []byte, lo, hi int) int {
	const bitfieldMoveMask, bitfieldMoveTag = 0x7F800000, 0x53000000
	immFields := uint32(0x3F<<16) | uint32(0x3F<<10)
	count := 0

	// Move tag extraction/insertion from bit 42 to bit 35 (ubfx #42,#3 / lsl #42).
	for off := lo; off < hi && off+4 <= len(data); off += 4 {
		w := word(data, off)
		if w&bitfieldMoveMask != bitfieldMoveTag {
			continue
		}
		immr := (w >> 16) & 0x3F
		imms := (w >> 10) & 0x3F
		switch {
		case immr == 42 && imms == 44:
			putWord(data, off, (w&^immFields)|(35<<16)|(37<<10))
			count++
		case immr == 22 && imms == 21:
			putWord(data, off, (w&^immFields)|(29<<16)|(28<<10))
			count++
		}
	}

	// Random-address mask pair -> 39-bit mask (0x7ffffffff).
	for off := lo; off < hi-4 && off+8 <= len(data); off += 4 {
		if word(data, off) == 0x92D3800A && word(data, off+4) == 0xF2E0000A {
			putWord(data, off, 0x9280000A)
			putWord(data, off+4, 0xD35DFD4A)
			count++
		}
	}

	// MmapAlignedLocked upper bound 1<<48 -> 1<<39.
	for off := lo; off < hi && off+4 <= len(data); off += 4 {
		if word(data, off) == 0xF2E00029 {
			putWord(data, off, 0xD3596129)
			count++
		}
	}

	// Inlined tag constants and fast-path dealloc masks.
	for off := lo; off < hi && off+4 <= len(data); off += 4 {
		if rep, ok := tagConstants[word(data, off)]; ok {
			putWord(data, off, rep)
			count++
		}
	}
	return count
}

// patchFaccessat2 rewrites every `mov x0, #439` (faccessat2) that sets up an
// immediately-following syscall branch to `mov x0, #48` (faccessat).
func patchFaccessat2(data []byte) int {
	count := 0
	for off := 0; off+16 <= len(data); off += 4 {
		if word(data, off) == 0xAA1F03E5 &&
			word(data, off+4) == 0xAA1F03E6 &&
			word(data, off+8) == 0xD28036E0 &&
			word(data, off+12)&0xFC000000 == 0x94000000 {
			putWord(data, off+8, 0xD2800600)
			count++
		}
	}
	return count
}
