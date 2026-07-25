#
# user core constraints
#
# put your clock groups in here as well as any net assignments
#

# A2b (2026-07-23): copro rides clk_85_9/2 = 42.95 MHz (distinct from host clk_ppu_21_47).
# clk_copro is a fabric /2 of outclk_0 (clk_85_9), VCO-related to outclk_0/1 -> joins their
# synchronous group so the copro<->host crossing is TIMED (not false-pathed; phase-locked).
# NOTE: verify the target pin on first synthesis (register nes_top.clk_copro = ic|nes|clk_copro).
create_generated_clock -name clk_copro -divide_by 2 \
 -source [get_pins {ic|mp1|mf_pllbase_inst|altera_pll_i|*[0].*|divclk}] \
 [get_pins {ic|nes|clk_copro|q}]

set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|*[0].*|divclk \
          ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk \
          clk_copro } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|*[2].*|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|*[3].*|divclk } \
 -group { ic|audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk }

derive_clock_uncertainty

set_multicycle_path -from {ic|nes|sdram|*} -to [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] -start -setup 2
set_multicycle_path -from {ic|nes|sdram|*} -to [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] -start -hold 1

set_multicycle_path -from [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] -to {ic|nes|sdram|*} -setup 2
set_multicycle_path -from [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk}] -to {ic|nes|sdram|*} -hold 1

set_false_path -from {ic|nes|mapper_flags*}
#set_false_path -from {ic|nes|downloading*}
