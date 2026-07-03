module axi_stream_ctrl 
(
    input                           eth_mac_rst,    
    input                           s_eth_tx_clk,
    input                           s_eth_tx_tvalid,
    output                          s_eth_tx_tready,
    input    [7:0]                  s_eth_tx_tdata,
    input    [0:0]                  s_eth_tx_tkeep,
    input    [3:0]                  s_eth_tx_tdest,
    input                           s_eth_tx_tlast,

    output                          m_eth_tx_tvalid,
    input                           m_eth_tx_tready,
    output    [7:0]                 m_eth_tx_tdata,
    output    [3:0]                 m_eth_tx_tdest,
    output                          m_eth_tx_tlast,
    
    input       [31:0]              tx_packet_count
);

reg         r_eth_tx_tvalid;
reg [7:0]   r_eth_tx_tdata;
reg [3:0]   r_eth_tx_tdest;

assign m_eth_tx_tvalid = r_eth_tx_tvalid;
assign s_eth_tx_tready = m_eth_tx_tready;
assign m_eth_tx_tdata = r_eth_tx_tdata;
assign m_eth_tx_tdest = r_eth_tx_tdest;
assign m_eth_tx_tlast = (r_packet_cnt==tx_packet_count)?1'b1:1'b0;

reg [31:0] r_packet_cnt;

always@(posedge s_eth_tx_clk or posedge eth_mac_rst)
begin
    if(eth_mac_rst)
    begin
        r_eth_tx_tvalid     <= 1'b0;
        r_eth_tx_tdata      <= 8'b0;
        r_eth_tx_tdest      <= 4'b0;
        r_packet_cnt        <= 32'b0;
    end
    else
    begin
        if(s_eth_tx_tkeep && s_eth_tx_tvalid)
        begin
            r_packet_cnt   <= r_packet_cnt +1'b1;
        end
    
        r_eth_tx_tvalid <=(s_eth_tx_tkeep && s_eth_tx_tvalid);
        r_eth_tx_tdata <=  s_eth_tx_tdata;      
        r_eth_tx_tdest <=  s_eth_tx_tdest;
       
       if(r_packet_cnt==tx_packet_count)
            r_packet_cnt <=32'b0;
    end
end

endmodule