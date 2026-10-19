`timescale 1ns/1ps
`default_nettype none

module tb_mult;
    reg clk;
    reg rst_n;
    reg [3:0] a;
    reg [3:0] b;
    wire [7:0] p;
    integer ai, bi;
    integer checked;
    integer errors;
    integer half_period;
    integer stream_checked, reset_checked;
    reg [7:0] expected;
    reg [7:0] queued_product;
    reg [7:0] operand_pair;
    reg [255:0] seen_pairs;
    reg [15:0] reset_nonzero_seen;

    mult_array dut (.clk(clk), .rst_n(rst_n), .a(a), .b(b), .p(p));

    initial begin
        clk = 1'b0;
        // Default: 10 ns. A slower clock can accommodate functional gate delays.
        if (!$value$plusargs("HALF_PERIOD=%d", half_period)) half_period = 5;
        if (half_period < 3) $fatal(1, "HALF_PERIOD must be at least 3 ns");
        forever #(half_period) clk = ~clk;
    end

    // A second oracle, independent of the multiplication used in the basic test.
    function [7:0] shift_add_product(input [3:0] x, input [3:0] y);
        integer bit_index;
        begin
            shift_add_product = 0;
            for (bit_index = 0; bit_index < 4; bit_index = bit_index + 1)
                if (y[bit_index])
                    shift_add_product = shift_add_product + ({4'b0, x} << bit_index);
        end
    endfunction

    // Check the preceding transaction at every capture edge, not the new input.
    task stream_step(input [7:0] pair);
        begin
            @(negedge clk);
            a = pair[7:4];
            b = pair[3:0];
            @(posedge clk);
            #2;
            if (p !== queued_product)
                $fatal(1, "PIPELINE: a=%0d b=%0d expected(previous)=%0d got=%0d",
                       a, b, queued_product, p);
            queued_product = shift_add_product(a, b);
        end
    endtask

    task occupied_reset(input [7:0] pair);
        begin
            stream_step(pair);
            stream_step(pair);
            if ({dut.a_reg, dut.b_reg, p} !== {pair, shift_add_product(pair[7:4], pair[3:0])})
                $fatal(1, "RESET: pipeline was not filled with the requested operands");
            reset_nonzero_seen = reset_nonzero_seen | {dut.a_reg, dut.b_reg, p};
            // Assert and inspect reset strictly before the next rising clock edge.
            @(negedge clk);
            #1; rst_n = 1'b0;
            #2;
            if ({dut.a_reg, dut.b_reg, p} !== 16'b0)
                $fatal(1, "ASYNC RESET: registers did not clear before the next clock edge");
            reset_checked = reset_checked + 1;
            @(negedge clk);
            a = 0;
            b = 0;
            rst_n = 1'b1;
            queued_product = 0;
        end
    endtask

    initial begin
        $dumpfile("mult.vcd");
        $dumpvars(0, tb_mult);
        rst_n = 1'b0;
        a = 4'd0;
        b = 4'd0;
        checked = 0;
        errors = 0;

        // Hold reset for exactly the first two full clock periods.
        // Counting rising edges avoids a possible X-to-0 clock event at time 0.
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        for (ai = 0; ai < 16; ai = ai + 1) begin
            for (bi = 0; bi < 16; bi = bi + 1) begin
                // Drive on falling edges to avoid a race with input capture.
                @(negedge clk);
                a = ai[3:0];
                b = bi[3:0];
                expected = ai * bi; // Reference multiplication only in the TB.
                // Edge 1 captures a/b; edge 2 captures their product.
                repeat (2) @(posedge clk);
                #2; // Past nonblocking assignments and the GLS flop unit delay.
                checked = checked + 1;
                if (p !== expected) begin
                    errors = errors + 1;
                    $display("MISMATCH: a=%0d b=%0d expected=%0d got=%0d time=%0t",
                             ai, bi, expected, p, $time);
                end
            end
        end

        if (errors == 0 && checked == 256)
            $display("PASS: %0d vectors checked, 0 errors", checked);
        else
            $display("FAIL: %0d vectors checked, %0d errors", checked, errors);
        // A failing test also supplies a nonzero process exit status.
        if (errors != 0 || checked != 256)
            $fatal(1, "Exhaustive multiplier verification failed or coverage was incomplete");

        // Optional stronger checks preserve the required default test and output.
        if ($test$plusargs("EXTENDED")) begin
            if (half_period < 5)
                $fatal(1, "EXTENDED requires HALF_PERIOD >= 5 for off-edge reset checks");
            queued_product = shift_add_product(a, b);
            stream_checked = 0;
            reset_checked = 0;
            seen_pairs = 0;
            reset_nonzero_seen = 0;
            occupied_reset(8'hff);
            for (ai = 0; ai < 256; ai = ai + 1) begin
                // Multiplication by an odd number permutes all 256 operand pairs.
                operand_pair = (73 * ai + 19) & 255;
                if (seen_pairs[operand_pair]) $fatal(1, "Duplicate streamed input pair");
                stream_step(operand_pair);
                seen_pairs[operand_pair] = 1'b1;
                stream_checked = stream_checked + 1;
            end
            stream_step(8'h00); // Drain the final streamed transaction.
            occupied_reset(8'hed);
            occupied_reset(8'hb7);
            stream_step(8'h12);
            stream_step(8'hb7);
            stream_step(8'h00); // Check pipeline restart and drain again.
            if (stream_checked != 256 || seen_pairs !== {256{1'b1}} ||
                reset_checked != 3 || reset_nonzero_seen !== 16'hffff)
                $fatal(1, "Extended coverage was incomplete");
            $display("EXTENDED PASS: %0d unique pairs streamed, exact pipeline latency checked, %0d off-edge resets, all 16 register bits exercised",
                     stream_checked, reset_checked);
        end
        $finish;
    end
endmodule

`default_nettype wire
