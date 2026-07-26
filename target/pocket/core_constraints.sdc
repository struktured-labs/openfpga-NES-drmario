#
# user core constraints
#
# put your clock groups in here as well as any net assignments
#

# Clock-bump (2026-07-25): the copro rides its OWN dedicated PLL tap, outclk_4 (index [4]),
# = VCO/11 = 54.669 MHz. It is auto-created by the altera_pll IP (no create_generated_clock
# needed -- the old fabric clk_85_9/2 divider is gone).
# The copro<->host crossing is ASYNCHRONOUS-SAFE by construction (host->copro reset/GO is a
# 2FF synchronizer rst_m/cpu_rst; board-in and results/DONE-out go through a true dual-port
# work RAM with flag-after-data ordering). The ONLY register-to-register cross path is the
# synchronizer input rst_cnt[*]->rst_m, which must NOT be timed. At the old ÷2 (phase-locked
# 2:1) timing it was free; at outclk_4 (28:11 vs host) the tight beat makes that synchronizer
# input fail setup by ~1.3ns even though intra-copro closes with +1.69ns. So the copro clock
# gets its OWN async group -> the synchronizer/BRAM crossing is correctly CUT, intra-copro
# stays timed. clk_85_9(outclk_0)+clk_ppu_21_47(outclk_1) stay grouped (real sdram<->host paths).

set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|*[0].*|divclk \
          ic|mp1|mf_pllbase_inst|altera_pll_i|*[1].*|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|*[4].*|divclk } \
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
