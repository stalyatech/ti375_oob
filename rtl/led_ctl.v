/////////////////////////////////////////////////////////////////////////////////
//
// EFINIX INC Confidential
// Copyright 2019, Efinix Inc., all rights reserved.
//
// Description:
// Pulse Generator Fast to Slow clock domain. This module will generate a 
// single pulse to slow clock domain.
//
// Language  : Verilog 2001
//
//
// ------------------------------------------------------------------------------
// REVISION:
//  $Snapshot: $
//  $Id:$
//
// History:
// 1.0 Initial Release. 
/////////////////////////////////////////////////////////////////////////////////
`resetall
`timescale 1ns / 1ps


module led_ctl
    (
     //outputs
     output led_o,
     
     //inputs
     input clk,
     input rst_n
     );

   reg [31:0] led_cnt;
   reg 	      led_out;
   

   localparam count = 'd125000000 - 1;

   always @(posedge clk or negedge rst_n)
     if (~rst_n)
       led_out <= 1'b0;
     else if (led_cnt == count)
       led_out <= ~led_out;

   always @(posedge clk or negedge rst_n)
     if (~rst_n)
       led_cnt <= 'd0;
     else if (led_cnt == count)
       led_cnt <= 'd0;
     else
       led_cnt <= led_cnt + 1;
   
   assign led_o = led_out;
   
endmodule // led_ctl

