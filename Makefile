BUILD_DIR := build
GAME_TRD := $(BUILD_DIR)/dicewars.trd

.PHONY: build run stop clean

# sources -> bootable .trd (fonts/music regenerated, game assembled, disk packed)
build:
	python3 tools/build_dicewars.py $(GAME_TRD) --build-dir $(BUILD_DIR) --force

# build, then boot it in the bundled ZEsarUX: enter TR-DOS and RUN "boot"
run: build
	python3 tools/zx_control.py stop || true
	python3 tools/zx_control.py launch --trd $(GAME_TRD) --window
	sleep 1
	python3 tools/zx_control.py boot-trdos
	sleep 1
	python3 tools/zx_control.py press ENTER
	sleep 0.3
	python3 tools/zx_control.py press R ENTER

stop:
	python3 tools/zx_control.py stop || true

clean:
	rm -rf $(BUILD_DIR)
