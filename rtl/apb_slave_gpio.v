// APB3 GPIO Register Slave
// 4 registers: DATA(0x00), DIR(0x04), INT_EN(0x08), INT_STATUS(0x0C)
// Address range: 0x1000-0x1FFF
// Interrupt: gpio_int = |(INT_STATUS & INT_EN)

module apb_slave_gpio (
    input  wire         pclk,
    input  wire         presetn,
    input  wire         psel,
    input  wire         penable,
    input  wire         pwrite,
    input  wire [31:0]  paddr,
    input  wire [31:0]  pwdata,
    output reg  [31:0]  prdata,
    output reg          pready,
    output wire         gpio_int
);

    reg [31:0] reg_data;
    reg [31:0] reg_dir;
    reg [31:0] reg_int_en;
    reg [31:0] reg_int_status;

    assign gpio_int = |(reg_int_status & reg_int_en);

    // APB write
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            reg_data       <= 32'd0;
            reg_dir        <= 32'd0;
            reg_int_en     <= 32'd0;
            reg_int_status <= 32'd0;
        end else if (psel && penable && pwrite) begin
            case (paddr[3:2])
                2'd0: reg_data       <= pwdata;
                2'd1: reg_dir        <= pwdata;
                2'd2: reg_int_en     <= pwdata;
                2'd3: reg_int_status <= pwdata;
            endcase
        end
    end

    // APB read
    always @(*) begin
        case (paddr[3:2])
            2'd0: prdata = reg_data;
            2'd1: prdata = reg_dir;
            2'd2: prdata = reg_int_en;
            2'd3: prdata = reg_int_status;
            default: prdata = 32'd0;
        endcase
    end

    // PREADY — always ready
    always @(posedge pclk or negedge presetn) begin
        if (!presetn)
            pready <= 1'b1;
        else if (psel && penable)
            pready <= 1'b1;
        else
            pready <= 1'b1;
    end

endmodule
