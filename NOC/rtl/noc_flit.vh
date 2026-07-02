// noc_flit.vh — Flit type definitions (Verilog-2001)
`ifndef NOC_FLIT_VH
`define NOC_FLIT_VH

  // Flit encoding
  `define FLIT_TYPE_W    2
  `define FLIT_PAYLOAD_W 510
  `define FLIT_W         512           // FLIT_PAYLOAD_W + FLIT_TYPE_W

  // Flit type constants
  `define FLIT_IDLE      2'b00
  `define FLIT_HEADER    2'b01
  `define FLIT_BODY      2'b10
  `define FLIT_TAIL      2'b11

  // Header field widths and positions (MSB-justified in payload[509:0])
  // flit_header_t packed struct (82 bits total):
  //   dst_y[2:0] dst_x[2:0] src_y[2:0] src_x[2:0] qos[3:0] axlen[7:0]
  //   axid[7:0] axaddr[31:0] axburst[1:0] axsize[3:0] axlock[3:0]
  //   axcache[1:0] axprot[3:0] is_read is_response

  `define HDR_W          82
  `define HDR_HI         509
  `define HDR_LO         (509 - `HDR_W + 1)  // = 428

  // Field bit ranges in payload[509:0]
  // dst_y[2:0] @ [509:507]
  `define HDR_DST_Y_HI   509
  `define HDR_DST_Y_LO   507
  // dst_x[2:0] @ [506:504]
  `define HDR_DST_X_HI   506
  `define HDR_DST_X_LO   504
  // src_y[2:0] @ [503:501]
  `define HDR_SRC_Y_HI   503
  `define HDR_SRC_Y_LO   501
  // src_x[2:0] @ [500:498]
  `define HDR_SRC_X_HI   500
  `define HDR_SRC_X_LO   498
  // qos[3:0] @ [497:494]
  `define HDR_QOS_HI     497
  `define HDR_QOS_LO     494
  // axlen[7:0] @ [493:486]
  `define HDR_AXLEN_HI   493
  `define HDR_AXLEN_LO   486
  // axid[7:0] @ [485:478]
  `define HDR_AXID_HI    485
  `define HDR_AXID_LO    478
  // axaddr[31:0] @ [477:446]
  `define HDR_AXADDR_HI  477
  `define HDR_AXADDR_LO  446
  // axburst[1:0] @ [445:444]
  `define HDR_AXBURST_HI 445
  `define HDR_AXBURST_LO 444
  // axsize[3:0] @ [443:440]
  `define HDR_AXSIZE_HI  443
  `define HDR_AXSIZE_LO  440
  // axlock[3:0] @ [439:436]
  `define HDR_AXLOCK_HI  439
  `define HDR_AXLOCK_LO  436
  // axcache[1:0] @ [435:434]
  `define HDR_AXCACHE_HI 435
  `define HDR_AXCACHE_LO 434
  // axprot[3:0] @ [433:430]
  `define HDR_AXPROT_HI  433
  `define HDR_AXPROT_LO  430
  // is_read @ [429]
  `define HDR_IS_READ    429
  // is_response @ [428]
  `define HDR_IS_RESPONSE 428

  // Convenience extraction macros: extract field from 510-bit payload
  `define FLIT_HDR_DST_Y(p)     p[`HDR_DST_Y_HI:`HDR_DST_Y_LO]
  `define FLIT_HDR_DST_X(p)     p[`HDR_DST_X_HI:`HDR_DST_X_LO]
  `define FLIT_HDR_SRC_Y(p)     p[`HDR_SRC_Y_HI:`HDR_SRC_Y_LO]
  `define FLIT_HDR_SRC_X(p)     p[`HDR_SRC_X_HI:`HDR_SRC_X_LO]
  `define FLIT_HDR_QOS(p)       p[`HDR_QOS_HI:`HDR_QOS_LO]
  `define FLIT_HDR_AXLEN(p)     p[`HDR_AXLEN_HI:`HDR_AXLEN_LO]
  `define FLIT_HDR_AXID(p)      p[`HDR_AXID_HI:`HDR_AXID_LO]
  `define FLIT_HDR_AXADDR(p)    p[`HDR_AXADDR_HI:`HDR_AXADDR_LO]
  `define FLIT_HDR_AXBURST(p)   p[`HDR_AXBURST_HI:`HDR_AXBURST_LO]
  `define FLIT_HDR_AXSIZE(p)    p[`HDR_AXSIZE_HI:`HDR_AXSIZE_LO]
  `define FLIT_HDR_AXLOCK(p)    p[`HDR_AXLOCK_HI:`HDR_AXLOCK_LO]
  `define FLIT_HDR_AXCACHE(p)   p[`HDR_AXCACHE_HI:`HDR_AXCACHE_LO]
  `define FLIT_HDR_AXPROT(p)    p[`HDR_AXPROT_HI:`HDR_AXPROT_LO]
  `define FLIT_HDR_IS_READ(p)   p[`HDR_IS_READ]
  `define FLIT_HDR_IS_RESPONSE(p) p[`HDR_IS_RESPONSE]

  // Build a header payload from individual fields
  `define FLIT_HDR_PACK(dst_y, dst_x, src_y, src_x, qos, axlen, axid, axaddr, axburst, axsize, axlock, axcache, axprot, is_read, is_response) \
    {dst_y[2:0], dst_x[2:0], src_y[2:0], src_x[2:0], qos[3:0], axlen[7:0], axid[7:0], axaddr[31:0], axburst[1:0], axsize[3:0], axlock[3:0], axcache[1:0], axprot[3:0], is_read, is_response, {(`HDR_LO){1'b0}}}

  // Extract body data from payload
  `define FLIT_BODY_DATA(p)   p[509:64]
  `define FLIT_BODY_WSTRB(p)  p[63:0]

  // Construct body flit payload
  `define FLIT_BODY_PACK(data, wstrb) {data[445:0], wstrb[63:0]}

  // Get src/dst node ID from header payload
  `define FLIT_HDR_SRC_ID(p)  {`FLIT_HDR_SRC_Y(p), `FLIT_HDR_SRC_X(p)}
  `define FLIT_HDR_DST_ID(p)  {`FLIT_HDR_DST_Y(p), `FLIT_HDR_DST_X(p)}

`endif
