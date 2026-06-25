// APB3 GPIO Register Slave
// 4 registers: DATA(0x00), DIR(0x04), INT_EN(0x08), INT_STATUS(0x0C)
// Address range: 0x1000-0x1FFF
// INT_STATUS: write-1-to-clear (W1C) semantics — hardware sets, software clears
// External pins: gpio_in[31:0], gpio_out[31:0]
// gpio_out = reg_data & reg_dir (only pins with DIR=1 drive output)
// Interrupt: gpio_int = |(INT_STATUS & INT_EN)

module apb_slave_gpio (
    input  wire         pclk,
    input  wire         presetn,
    input  wire         psel,
    input  wire         penable,
    input  wire         pwrite,
    input  wire [31:0]  paddr,
    input  wire [31:0]  pwdata,
    input  wire [3:0]   pwstrb,
    output reg  [31:0]  prdata,
    output reg          pready,
    output wire         gpio_int,
    input  wire [31:0]  gpio_in,
    output wire [31:0]  gpio_out
);

    reg [31:0] reg_data;
    reg [31:0] reg_dir;
    reg [31:0] reg_int_en;
    reg [31:0] reg_int_status;

    // gpio_in edge detector — rising edge on gpio_in sets INT_STATUS bit
    reg [31:0] gpio_in_d;
    wire [31:0] gpio_in_rise = gpio_in & ~gpio_in_d;

    // gpio_out = DATA masked by DIR
    assign gpio_out = reg_data & reg_dir;

    // gpio_int = AND of INT_STATUS and INT_EN
    assign gpio_int = |(reg_int_status & reg_int_en);

    // Byte-write helper: pwstrb[i] gates byte lane i
    function [31:0] masked_write(input [31:0] old_val, input [31:0] new_val, input [3:0] strb);
        masked_write = {
            strb[3] ? new_val[31:24] : old_val[31:24],
            strb[2] ? new_val[23:16] : old_val[23:16],
            strb[1] ? new_val[15: 8] : old_val[15: 8],
            strb[0] ? new_val[ 7: 0] : old_val[ 7: 0]
        };
    endfunction

    // APB write + gpio_in edge detection + W1C for INT_STATUS
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            reg_data       <= 32'd0;
            reg_dir        <= 32'd0;
            reg_int_en     <= 32'd0;
            reg_int_status <= 32'd0;
            gpio_in_d      <= 32'd0;
        end else begin
            // Synchronize gpio_in for edge detection
            gpio_in_d <= gpio_in;

            // INT_STATUS: hardware sets bits on gpio_in rising edge,
            // software clears via W1C. Combine both in one assignment.
            if (psel && penable && pwrite && (paddr[3:2] == 2'd3))
                reg_int_status <= (reg_int_status | gpio_in_rise) & (~pwdata);
            else
                reg_int_status <=  reg_int_status | gpio_in_rise;

            // Other register writes
            if (psel && penable && pwrite) begin
                case (paddr[3:2])
                    2'd0: reg_data   <= masked_write(reg_data,   pwdata, pwstrb);
                    2'd1: reg_dir    <= masked_write(reg_dir,    pwdata, pwstrb);
                    2'd2: reg_int_en <= masked_write(reg_int_en, pwdata, pwstrb);
                endcase
            end
        end
    end

    // APB read — combinational, gated by psel
    always @(*) begin
        if (psel) begin
            case (paddr[3:2])
                2'd0: prdata = reg_data;
                2'd1: prdata = reg_dir;
                2'd2: prdata = reg_int_en;
                2'd3: prdata = reg_int_status;
                default: prdata = 32'd0;
            endcase
        end else begin
            prdata = 32'd0;
        end
    end

    // PREADY — 1'b1 only during ACCESS phase
    always @(posedge pclk or negedge presetn) begin
        if (!presetn)
            pready <= 1'b0;
        else if (psel && penable)
            pready <= 1'b1;
        else
            pready <= 1'b0;
    end

endmodule
