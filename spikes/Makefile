SWIFTC      ?= swiftc
SWIFTFLAGS  ?= -O
BIN         := bin
SRC         := Sources

ALL := $(BIN)/spike-temps $(BIN)/spike-fans $(BIN)/spike-gpu

.PHONY: all clean temps fans gpu

all: $(ALL)

$(BIN):
	@mkdir -p $(BIN)

# Each spike is compiled as a single Swift module via direct `swiftc` calls.
# This intentionally bypasses Swift Package Manager: the CLT-bundled
# `libPackageDescription.dylib` references init symbols that aren't present
# in the same dylib (typealias-vs-type ABI mismatch on `SwiftVersion` →
# `SwiftLanguageMode`), making `swift build` non-functional with only CLT
# installed. Direct `swiftc` works fine.

$(BIN)/spike-temps: $(BIN) $(SRC)/SpikeTemps/main.swift
	$(SWIFTC) $(SWIFTFLAGS) -framework IOKit -o $@ $(SRC)/SpikeTemps/main.swift

$(BIN)/spike-fans: $(BIN) $(SRC)/SMCKit/SMC.swift $(SRC)/SpikeFans/main.swift
	$(SWIFTC) $(SWIFTFLAGS) -framework IOKit -o $@ \
		$(SRC)/SMCKit/SMC.swift $(SRC)/SpikeFans/main.swift

$(BIN)/spike-gpu: $(BIN) $(SRC)/SpikeGPU/main.swift
	$(SWIFTC) $(SWIFTFLAGS) -o $@ $(SRC)/SpikeGPU/main.swift

temps: $(BIN)/spike-temps
	./$(BIN)/spike-temps

fans: $(BIN)/spike-fans
	./$(BIN)/spike-fans

gpu: $(BIN)/spike-gpu
	./$(BIN)/spike-gpu

clean:
	rm -rf $(BIN)
