// APB3 Bus System — Top Level
// 2 Masters → Arbiter → Decoder → 2 Slaves (Memory + GPIO)

module apb_top (
    input  wire         pclk,
    input  wire         presetn,

    // Master 0 txn stimulus (from testbench)
    input  wire         txn_req_0,
    input  wire [31:0]  txn_addr_0,
    input  wire [31:0]  txn_wdata_0,
    input  wire         txn_write_0,

    // Master 1 txn stimulus (from testbench)
    input  wire         txn_req_1,
    input  wire [31:0]  txn_addr_1,
    input  wire [31:0]  txn_wdata_1,
    input  wire         txn_write_1,

    // Per-master req/gnt (exposed for monitoring)
    output wire         req_0,
    output wire         gnt_0,
    output wire         req_1,
    output wire         gnt_1,

    // Shared APB bus (exposed for monitoring)
    output wire [31:0]  paddr,
    output wire [31:0]  pwdata,
    output wire [31:0]  prdata,
    output wire         pwrite,
    output wire         psel,
    output wire         penable,
    output wire         pready,

    // Slave selects
    output wire [1:0]   psel_slv,

    // GPIO interrupt
    output wire         gpio_int
);

    // Internal connections
    wire [31:0] m0_paddr, m0_pwdata, m1_paddr, m1_pwdata;
    wire        m0_pwrite, m0_psel, m0_penable;
    wire        m1_pwrite, m1_psel, m1_penable;

    wire [31:0] arb_paddr, arb_pwdata;
    wire        arb_pwrite, arb_psel, arb_penable;
    wire        arb_pready;

    wire [31:0] prdata_slv0, prdata_slv1;
    wire        pready_slv0, pready_slv1;

    // Master 0
    apb_master #(.MASTER_ID(0)) u_master0 (
        .pclk      (pclk),
        .presetn   (presetn),
        .req       (req_0),
        .gnt       (gnt_0),
        .paddr     (m0_paddr),
        .pwdata    (m0_pwdata),
        .prdata    (prdata),
        .pwrite    (m0_pwrite),
        .psel      (m0_psel),
        .penable   (m0_penable),
        .pready    (pready),
        .txn_req   (txn_req_0),
        .txn_addr  (txn_addr_0),
        .txn_wdata (txn_wdata_0),
        .txn_write (txn_write_0)
    );

    // Master 1
    apb_master #(.MASTER_ID(1)) u_master1 (
        .pclk      (pclk),
        .presetn   (presetn),
        .req       (req_1),
        .gnt       (gnt_1),
        .paddr     (m1_paddr),
        .pwdata    (m1_pwdata),
        .prdata    (prdata),
        .pwrite    (m1_pwrite),
        .psel      (m1_psel),
        .penable   (m1_penable),
        .pready    (pready),
        .txn_req   (txn_req_1),
        .txn_addr  (txn_addr_1),
        .txn_wdata (txn_wdata_1),
        .txn_write (txn_write_1)
    );

    // Arbiter
    apb_arbiter u_arbiter (
        .pclk      (pclk),
        .presetn   (presetn),
        .req_0     (req_0),
        .gnt_0     (gnt_0),
        .paddr_0   (m0_paddr),
        .pwdata_0  (m0_pwdata),
        .pwrite_0  (m0_pwrite),
        .psel_0    (m0_psel),
        .penable_0 (m0_penable),
        .req_1     (req_1),
        .gnt_1     (gnt_1),
        .paddr_1   (m1_paddr),
        .pwdata_1  (m1_pwdata),
        .pwrite_1  (m1_pwrite),
        .psel_1    (m1_psel),
        .penable_1 (m1_penable),
        .paddr     (arb_paddr),
        .pwdata    (arb_pwdata),
        .pwrite    (arb_pwrite),
        .psel      (arb_psel),
        .penable   (arb_penable),
        .pready    (arb_pready)
    );

    // Decoder
    apb_decoder u_decoder (
        .paddr   (arb_paddr),
        .psel_in (arb_psel),
        .psel_o  (psel_slv)
    );

    // Slave 0: Memory
    apb_slave_mem #(.STALL_PROB(64)) u_slave_mem (
        .pclk    (pclk),
        .presetn (presetn),
        .psel    (psel_slv[0]),
        .penable (arb_penable),
        .pwrite  (arb_pwrite),
        .paddr   (arb_paddr),
        .pwdata  (arb_pwdata),
        .prdata  (prdata_slv0),
        .pready  (pready_slv0)
    );

    // Slave 1: GPIO
    apb_slave_gpio u_slave_gpio (
        .pclk     (pclk),
        .presetn  (presetn),
        .psel     (psel_slv[1]),
        .penable  (arb_penable),
        .pwrite   (arb_pwrite),
        .paddr    (arb_paddr),
        .pwdata   (arb_pwdata),
        .prdata   (prdata_slv1),
        .pready   (pready_slv1),
        .gpio_int (gpio_int)
    );

    // PRDATA + PREADY mux from slaves to shared bus
    assign prdata     = psel_slv[0] ? prdata_slv0 :
                        psel_slv[1] ? prdata_slv1 : 32'd0;
    assign arb_pready = psel_slv[0] ? pready_slv0 :
                        psel_slv[1] ? pready_slv1 : 1'b1;

    // Drive shared bus outputs
    assign paddr   = arb_paddr;
    assign pwdata  = arb_pwdata;
    assign pwrite  = arb_pwrite;
    assign psel    = arb_psel;
    assign penable = arb_penable;
    assign pready  = arb_pready;

endmodule
