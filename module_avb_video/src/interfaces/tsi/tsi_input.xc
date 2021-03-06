#include <xs1.h>
#include <platform.h>

#include "tsi_input.h"
#include "avb_conf.h"

#if AVB_NUM_MEDIA_INPUTS > 0

// Uncomment this is you would like to check that the timing is good for 8 threads
//#pragma xta command "config threads stdcore[0] 8"

#pragma xta command "remove exclusion *"
#pragma xta command "add exclusion ts_spi_input_start"
#pragma xta command "analyze endpoints ts_spi_input_first ts_spi_input_loop"
#pragma xta command "set required - 148 ns"

#pragma xta command "remove exclusion *"
#pragma xta command "add exclusion ts_spi_input_start"
#pragma xta command "add exclusion ts_spi_input_loop"
#pragma xta command "analyze endpoints ts_spi_input_loop ts_spi_input_first"
#pragma xta command "set required - 148 ns"

// 0001 = 1 = correct (drop 4)
// 0010 = 2 = drop 3
// 0100 = 4 = drop 2
// 1000 = 8 = drop 1
static const char align_byte[16] = { 32, 32, 24, 32, 16, 32, 32, 32, 8, 32, 32, 32, 32, 32, 32, 32 };

static unsigned overflow=0;
static unsigned stream_start=0;

#pragma unsafe arrays
void tsi_input(clock clk, in buffered port:32 p_data, in port p_clk, in buffered port:4 p_sync, in port p_valid, ififo_t& ififo)
{
	unsigned wr_ptr = 0, sync;
	timer t;

	// Intialise port, clearbufs and start clock last
	configure_clock_src(clk, p_clk);
	configure_in_port_strobed_slave(p_data, p_valid, clk);
	configure_in_port_strobed_slave(p_sync, p_valid, clk);

	clearbuf(p_data);
	clearbuf(p_sync);

	start_clock(clk);

	while (1) {

#pragma xta endpoint "ts_spi_input_start"

		// Read sync word until it is non-zero then use bit position to find shift multiplier
		{
			unsigned v;
			stream_start++;
			p_sync when pinsneq(0) :> sync;
			partin(p_data, align_byte[v & 0xF]);

			for (unsigned n=0; n<46; n++) {
				p_data :> unsigned;
			}
		}

		while (1) {
			// Only execute the packet receive when there is space in the
			// buffer to accept it.  This form of loop in loop gives better
			// critical path cost because the end branch of the critical
			// inner loop is both the test and the branch back.
			unsigned advance;
			unsigned time, value;

			// Read first word
#pragma xta endpoint "ts_spi_input_first"
			p_data :> value;
			{
				unsigned s;
				p_sync :> s;
				if (s != sync) break;
			}

			// Check if this packet is free
			advance = (ififo.fifo[wr_ptr+MEDIA_INPUT_FIFO_INUSE_OFFSET] == 0);
			wr_ptr += advance;

			t :> time;
			ififo.fifo[wr_ptr] = time;
			wr_ptr += advance;
			ififo.fifo[wr_ptr] = value;
			wr_ptr += advance;


			// loop for main block of words
#pragma loop unroll
			for (unsigned n=0; n<46; n++) {
#pragma xta endpoint "ts_spi_input_loop"
				p_data :> value;
				ififo.fifo[wr_ptr] = value;
				wr_ptr += advance;
			}

			// Put in end marker
			ififo.fifo[wr_ptr] = advance; // write some end value
			wr_ptr += advance;

			// In the XMOS architecture, the various test instructions
			// return a value of 1 or 0 in a register, therefore the
			// result of a comparison like '<' is 1 or 0, and therefore
			// can be safely used as it is below
			wr_ptr *= (wr_ptr < MEDIA_INPUT_FIFO_WORD_SIZE);
		}
	}
}

#endif

