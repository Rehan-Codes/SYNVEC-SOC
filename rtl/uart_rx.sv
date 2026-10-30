`timescale 1ns/1ps





module uart_rx #(parameter integer DIVISOR = 868) (
    input  logic       clk,
    input  logic       reset_n,
    input  logic       rx_serial,
    input  logic       pop,
    input  logic       clear_flags,
    output logic [7:0] data,
    output logic       valid,
    output logic       overrun,
    output logic       framing_error,
    output logic       busy
);
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) logic rx_meta;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) logic rx_sync;
    typedef enum logic [2:0] {S_IDLE, S_START, S_DATA, S_STOP, S_WAIT_IDLE} state_t;
    state_t state;
    logic [15:0] timer;
    logic [2:0] bit_index;
    logic [7:0] shift_reg;

    assign busy = (state != S_IDLE);

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            state <= S_IDLE;
            timer <= '0;
            bit_index <= '0;
            shift_reg <= '0;
            data <= '0;
            valid <= 1'b0;
            overrun <= 1'b0;
            framing_error <= 1'b0;
        end else begin
            rx_meta <= rx_serial;
            rx_sync <= rx_meta;

            if (pop) valid <= 1'b0;
            if (clear_flags) begin
                overrun <= 1'b0;
                framing_error <= 1'b0;
            end

            case (state)
                S_IDLE: begin
                    if (!rx_sync) begin
                        state <= S_START;
                        timer <= (DIVISOR / 2) - 1;
                    end
                end
                S_START: begin
                    if (timer != 0) timer <= timer - 1'b1;
                    else if (!rx_sync) begin
                        state <= S_DATA;
                        timer <= DIVISOR - 1;
                        bit_index <= 0;
                    end else begin
                        state <= S_IDLE;
                    end
                end
                S_DATA: begin
                    if (timer != 0) timer <= timer - 1'b1;
                    else begin
                        shift_reg[bit_index] <= rx_sync;
                        timer <= DIVISOR - 1;
                        if (bit_index == 7) state <= S_STOP;
                        else bit_index <= bit_index + 1'b1;
                    end
                end
                S_STOP: begin
                    if (timer != 0) timer <= timer - 1'b1;
                    else begin
                        if (!rx_sync) begin



                            state <= S_WAIT_IDLE;
                            framing_error <= 1'b1;
                        end else if (valid && !pop) begin
                            state <= S_IDLE;
                            overrun <= 1'b1;
                        end else begin
                            state <= S_IDLE;
                            data <= shift_reg;
                            valid <= 1'b1;
                        end
                    end
                end
                S_WAIT_IDLE: if (rx_sync) state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
