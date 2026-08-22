# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

This application (name: DiceWars ZX) is a from-scratch remake of the classic
DiceWars game (original: Copyright (C) 2001 GAMEDESIGN, gamedesign.jp) for the
ZX Spectrum 128 platform, shipped as a bootable TR-DOS .trd disk image.

The game logic is ported from the sibling browser remake in `../dicewars`
(plain JS), adapted to the Spectrum's restrictions: the map is a 32x20 grid of
8x8 attribute cells (one cell = one colour attribute, so player colours never
clash), dice counts are printed as digits, and the soundtrack is a small
custom AY-3-8912 pattern player.

Everything on the disk is built from readable source: Z80 assembly for
sjasmplus, UTF-8 BASIC text, a text-bitmap font and a text tracker score.
`make build` turns `src/` into a bootable `.trd`; `make run` boots it in the
bundled ZEsarUX emulator.

Project organisation follows `../zx-openit` (same tools/, bin/, .claude
layout; the trd/basic/emulator tooling is copied from there).
