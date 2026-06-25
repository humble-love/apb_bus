// APB3 Bus Interface with clocking blocks for UVM driver/monitor

interface apb_if #(
    parameter int NUM_MASTERS = 2
) (
    input logic pclk,
    input logic presetn
);
    // APB3 signals
    logic [31:0]  paddr;
    logic [31:0]  pwdata;
    logic [31:0]  prdata;
    logic         pwrite;
    logic [3:0]   pwstrb;
    logic         psel;
    logic         penable;
    logic         pready;

    // GPIO external pins
    logic [31:0]  gpio_in;
    logic [31:0]  gpio_out;

    // Master request/grant (per master)
    logic [NUM_MASTERS-1:0] req;
    logic [NUM_MASTERS-1:0] gnt;

    // Per-master txn stimulus (driven by UVM driver, connected to apb_master ports)
    logic [NUM_MASTERS-1:0]        txn_req;
    logic [31:0] txn_addr [NUM_MASTERS];
    logic [31:0] txn_wdata [NUM_MASTERS];
    logic        txn_write [NUM_MASTERS];

    // Driver clocking block
    clocking drv_cb @(posedge pclk);
        output txn_req, txn_addr, txn_wdata, txn_write;
        input  gnt;
        input  prdata, pready;
    endclocking

    // Monitor clocking block
    clocking mon_cb @(posedge pclk);
        input paddr, pwdata, prdata, pwrite, pwstrb, psel, penable, pready;
        input req, gnt;
        input gpio_in, gpio_out;
    endclocking

    // Driver modport
    modport drv_mp (
        input  pclk, presetn,
        output txn_req, txn_addr, txn_wdata, txn_write,
        input  gnt, prdata, pready
    );

    // Monitor modport
    modport mon_mp (
        input pclk, presetn,
        input paddr, pwdata, prdata, pwrite, pwstrb, psel, penable, pready,
        input req, gnt,
        input gpio_in, gpio_out
    );

endinterface
