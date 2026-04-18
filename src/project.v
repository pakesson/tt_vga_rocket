/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_pakesson_vga_rocket (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // The VGA PMOD outputs are:
  // uo[0]: "R1"
  // uo[1]: "G1"
  // uo[2]: "B1"
  // uo[3]: "VSYNC"
  // uo[4]: "R0"
  // uo[5]: "G0"
  // uo[6]: "B0"
  // uo[7]: "HSYNC"

  wire hsync, vsync, video_active;
  wire [9:0] x, y;

  hvsync_generator hvsync_gen(
      .clk(clk),
      .reset(~rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(video_active),
      .hpos(x),
      .vpos(y)
  );

  reg [1:0] r, g, b;
  assign uo_out = {hsync, b[0], g[0], r[0], vsync, b[1], g[1], r[1]};

  assign uio_out = 8'b0;
  assign uio_oe  = 8'h0;

  localparam [3:0] ST_PAD_IDLE     = 4'd0;
  localparam [3:0] ST_LIGHT_ASCENT = 4'd1;
  localparam [3:0] ST_LOW_SKY      = 4'd2;
  localparam [3:0] ST_CLOUDS       = 4'd3;
  localparam [3:0] ST_MID_SKY      = 4'd4;
  localparam [3:0] ST_HIGH_SKY     = 4'd5;
  localparam [3:0] ST_DARK_ASCENT  = 4'd6;
  localparam [3:0] ST_SPACE_FADE   = 4'd7;
  localparam [3:0] ST_SPACE        = 4'd8;

  localparam [8:0] STAGE_FRAMES    = 9'd179;
  localparam [8:0] STAGE_FREE_RUN  = 9'h1ff;

  function [5:0] stage_rgb;
    input [3:0] st;
    begin
      case (st)
        ST_PAD_IDLE,
        ST_LIGHT_ASCENT: stage_rgb = {2'd1, 2'd2, 2'd3};
        ST_LOW_SKY:      stage_rgb = {2'd0, 2'd1, 2'd2};
        ST_CLOUDS:       stage_rgb = {2'd3, 2'd3, 2'd3};
        ST_MID_SKY:      stage_rgb = {2'd0, 2'd1, 2'd2};
        ST_HIGH_SKY:     stage_rgb = {2'd0, 2'd0, 2'd2};
        ST_DARK_ASCENT:  stage_rgb = {2'd0, 2'd0, 2'd1};
        default:         stage_rgb = {2'd0, 2'd0, 2'd0};
      endcase
    end
  endfunction

  wire frame_start = video_active && (x == 10'd0) && (y == 10'd0);

  reg [8:0] frame_count;
  reg [3:0] stage;
  reg [9:0] scroll_px;

  wire launched = (stage != ST_PAD_IDLE);

  wire [3:0] stage_next = (stage == ST_SPACE) ? ST_SPACE : stage + 1'b1;

  wire [8:0] stage_frame_max = (stage == ST_SPACE) ? STAGE_FREE_RUN :
                                                    STAGE_FRAMES;

  always @(posedge clk) begin
    if (!rst_n) begin
      frame_count <= 9'd0;
      stage <= ST_PAD_IDLE;
      scroll_px <= 10'd0;
    end else if (frame_start) begin
      if (frame_count == stage_frame_max) begin
        if (stage != ST_SPACE) begin
          frame_count <= 9'd0;
          stage <= stage_next;
        end
      end else begin
        frame_count <= frame_count + 9'd1;
      end

      if (launched)
        scroll_px <= scroll_px + 10'd2;
    end
  end

  reg [1:0] bg_r, bg_g, bg_b;
  reg [1:0] pix_r, pix_g, pix_b;
  reg [9:0] nose_half_w;
  reg [9:0] booster_nose_half_w;
  reg [9:0] flame_half_w;
  reg [9:0] booster_flame_half_w;
  reg star_bit;

  wire [9:0] scene_y = y - scroll_px;
  wire scene_y_valid = (y >= scroll_px);

  wire [9:0] star_scene_y = scene_y;

  wire flame_flicker = frame_count[1] ^ frame_count[3] ^ x[2] ^ y[1];

  wire [9:0] main_body_y_off = (stage == ST_SPACE) ? {1'b0, frame_count} : 10'd0;
  wire [9:0] main_nose_y_off = (stage == ST_SPACE) ? ((frame_count > 9'd115) ? 10'd115 : {1'b0, frame_count}) : 10'd0;
  wire [9:0] booster_y_off = (stage == ST_MID_SKY) ? {frame_count, 1'b0} : 10'd0;

  wire boosters_visible = (stage <= ST_MID_SKY);
  wire main_flame_on = launched && (stage < ST_SPACE);
  wire booster_flame_on = launched && (stage < ST_MID_SKY);

  wire [3:0] prev_stage = (stage == ST_PAD_IDLE) ? ST_PAD_IDLE : stage - 1'b1;

  wire transition_active = (stage != ST_PAD_IDLE) && (frame_count < 9'd60);
  wire [9:0] transition_y = {frame_count, 1'b0} + {frame_count, 2'b0} + {frame_count, 3'b0};
  wire use_prev_bg = transition_active && (y >= transition_y);

  wire [5:0] bg_cur_rgb = stage_rgb(stage);
  wire [5:0] bg_prev_rgb = stage_rgb(prev_stage);

  wire [9:0] main_body_top = 10'd160 + main_body_y_off;
  wire [9:0] main_body_bottom = 10'd392 + main_body_y_off;
  wire [9:0] main_nose_top = 10'd90 + main_nose_y_off;
  wire [9:0] main_nose_bottom = 10'd160 + main_nose_y_off;
  wire [9:0] booster_body_top = 10'd220 + booster_y_off;
  wire [9:0] booster_body_bottom = 10'd400 + booster_y_off;
  wire [9:0] booster_nose_top = 10'd190 + booster_y_off;
  wire [9:0] booster_flame_top = 10'd400 + booster_y_off;

  wire in_space = (stage >= ST_SPACE_FADE);
  wire show_end_text = (stage == ST_SPACE) && (frame_count >= 9'd340);

  always @* begin
    nose_half_w = 10'd0;
    booster_nose_half_w = 10'd0;
    flame_half_w = 10'd0;
    booster_flame_half_w = 10'd0;
    star_bit = 1'b0;

    if (use_prev_bg) begin
      bg_r = bg_prev_rgb[5:4];
      bg_g = bg_prev_rgb[3:2];
      bg_b = bg_prev_rgb[1:0];
    end else begin
      bg_r = bg_cur_rgb[5:4];
      bg_g = bg_cur_rgb[3:2];
      bg_b = bg_cur_rgb[1:0];
    end

    pix_r = bg_r;
    pix_g = bg_g;
    pix_b = bg_b;

    // Ground
    if (((stage == ST_PAD_IDLE) || (stage == ST_LIGHT_ASCENT)) && scene_y_valid && (scene_y >= 10'd384)) begin
      pix_r = 2'd1;
      pix_g = 2'd2;
      pix_b = 2'd0;
    end

    // Main rocket body
    if ((x >= 10'd286) && (x <= 10'd354) &&
        (y >= main_body_top) && (y <= main_body_bottom)) begin
      pix_r = 2'd2;
      pix_g = 2'd1;
      pix_b = 2'd0;
    end

    // Main rocket nose cone
    if ((y >= main_nose_top) && (y < main_nose_bottom)) begin
      nose_half_w = (y - main_nose_top) >> 1;
      if ((x >= (10'd320 - nose_half_w)) && (x <= (10'd320 + nose_half_w))) begin
        pix_r = 2'd3;
        pix_g = 2'd3;
        pix_b = 2'd3;
      end
    end

    // Side boosters
    if (boosters_visible) begin
      if ((x >= 10'd356) && (x <= 10'd384) &&
          (y >= booster_body_top) && (y <= booster_body_bottom)) begin
        pix_r = 2'd2;
        pix_g = 2'd2;
        pix_b = 2'd2;
      end

      if ((x >= 10'd256) && (x <= 10'd284) &&
          (y >= booster_body_top) && (y <= booster_body_bottom)) begin
        pix_r = 2'd2;
        pix_g = 2'd2;
        pix_b = 2'd2;
      end

      // Booster nose cones
      if ((y >= booster_nose_top) && (y < booster_body_top)) begin
        booster_nose_half_w = (y - booster_nose_top) >> 1;
        if ((x >= (10'd270 - booster_nose_half_w)) && (x <= (10'd270 + booster_nose_half_w))) begin
          pix_r = 2'd3;
          pix_g = 2'd3;
          pix_b = 2'd3;
        end
        if ((x >= (10'd370 - booster_nose_half_w)) && (x <= (10'd370 + booster_nose_half_w))) begin
          pix_r = 2'd3;
          pix_g = 2'd3;
          pix_b = 2'd3;
        end
      end
    end

    // Main engine flame
    if (main_flame_on && (y >= 10'd392) && (y < 10'd460)) begin
      flame_half_w = 10'd6 + ((y - 10'd392) >> 1);
      if (flame_flicker)
        flame_half_w = flame_half_w + 10'd3;

      if ((x >= (10'd320 - flame_half_w)) && (x <= (10'd320 + flame_half_w))) begin
        if ((x >= 10'd314) && (x <= 10'd326) && (y < 10'd432)) begin
          pix_r = 2'd3;
          pix_g = 2'd3;
          pix_b = 2'd3;
        end else if ((x >= (10'd320 - (flame_half_w >> 1))) &&
                     (x <= (10'd320 + (flame_half_w >> 1)))) begin
          pix_r = 2'd3;
          pix_g = 2'd3;
          pix_b = 2'd0;
        end else begin
          pix_r = 2'd3;
          pix_g = 2'd1;
          pix_b = 2'd0;
        end
      end
    end

    // Booster flames (disabled once boosters separate)
    if (booster_flame_on && (y >= booster_flame_top) && (y < (10'd456 + booster_y_off))) begin
      booster_flame_half_w = 10'd4 + ((y - booster_flame_top) >> 2);
      if (flame_flicker)
        booster_flame_half_w = booster_flame_half_w + 10'd2;

      if ((x >= (10'd270 - booster_flame_half_w)) && (x <= (10'd270 + booster_flame_half_w))) begin
        pix_r = 2'd3;
        pix_g = 2'd2;
        pix_b = 2'd0;
      end

      if ((x >= (10'd370 - booster_flame_half_w)) && (x <= (10'd370 + booster_flame_half_w))) begin
        pix_r = 2'd3;
        pix_g = 2'd2;
        pix_b = 2'd0;
      end
    end

    // Stars
    // TODO: This is not working that well...
    star_bit = ((x == 10'd74)  && (star_scene_y == 10'd41))  ||
               ((x == 10'd153) && (star_scene_y == 10'd97))  ||
               ((x == 10'd231) && (star_scene_y == 10'd176)) ||
               ((x == 10'd318) && (star_scene_y == 10'd58))  ||
               ((x == 10'd402) && (star_scene_y == 10'd212)) ||
               ((x == 10'd489) && (star_scene_y == 10'd123)) ||
               ((x == 10'd557) && (star_scene_y == 10'd251)) ||
               ((x == 10'd612) && (star_scene_y == 10'd33));

    if (in_space && star_bit) begin
      pix_r = 2'd3;
      pix_g = 2'd3;
      pix_b = 2'd3;
    end

    // End text: SPASIC
    if (show_end_text) begin
      if (
          // S
          (((x >= 10'd180) && (x < 10'd220) && (y >= 10'd24) && (y < 10'd32)) ||
           ((x >= 10'd180) && (x < 10'd220) && (y >= 10'd52) && (y < 10'd60)) ||
           ((x >= 10'd180) && (x < 10'd220) && (y >= 10'd80) && (y < 10'd88)) ||
           ((x >= 10'd180) && (x < 10'd188) && (y >= 10'd24) && (y < 10'd56)) ||
           ((x >= 10'd212) && (x < 10'd220) && (y >= 10'd56) && (y < 10'd88))) ||

          // P
          ((x >= 10'd228) && (x < 10'd236) && (y >= 10'd24) && (y < 10'd88)) ||
          ((x >= 10'd228) && (x < 10'd268) && (y >= 10'd24) && (y < 10'd32)) ||
          ((x >= 10'd228) && (x < 10'd268) && (y >= 10'd52) && (y < 10'd60)) ||
          ((x >= 10'd260) && (x < 10'd268) && (y >= 10'd24) && (y < 10'd60)) ||

          // A
          ((x >= 10'd276) && (x < 10'd284) && (y >= 10'd24) && (y < 10'd88)) ||
          ((x >= 10'd308) && (x < 10'd316) && (y >= 10'd24) && (y < 10'd88)) ||
          ((x >= 10'd276) && (x < 10'd316) && (y >= 10'd24) && (y < 10'd32)) ||
          ((x >= 10'd276) && (x < 10'd316) && (y >= 10'd52) && (y < 10'd60)) ||

          // S
          (((x >= 10'd324) && (x < 10'd364) && (y >= 10'd24) && (y < 10'd32)) ||
           ((x >= 10'd324) && (x < 10'd364) && (y >= 10'd52) && (y < 10'd60)) ||
           ((x >= 10'd324) && (x < 10'd364) && (y >= 10'd80) && (y < 10'd88)) ||
           ((x >= 10'd324) && (x < 10'd332) && (y >= 10'd24) && (y < 10'd56)) ||
           ((x >= 10'd356) && (x < 10'd364) && (y >= 10'd56) && (y < 10'd88))) ||

          // I
          ((x >= 10'd372) && (x < 10'd412) && (y >= 10'd24) && (y < 10'd32)) ||
          ((x >= 10'd372) && (x < 10'd412) && (y >= 10'd80) && (y < 10'd88)) ||
          ((x >= 10'd388) && (x < 10'd396) && (y >= 10'd24) && (y < 10'd88)) ||

          // C
          ((x >= 10'd420) && (x < 10'd460) && (y >= 10'd24) && (y < 10'd32)) ||
          ((x >= 10'd420) && (x < 10'd460) && (y >= 10'd80) && (y < 10'd88)) ||
          ((x >= 10'd420) && (x < 10'd428) && (y >= 10'd24) && (y < 10'd88))
         ) begin
        pix_r = 2'd3;
        pix_g = 2'd3;
        pix_b = 2'd3;
      end
    end

    if (!video_active) begin
      r = 2'd0;
      g = 2'd0;
      b = 2'd0;
    end else begin
      r = pix_r;
      g = pix_g;
      b = pix_b;
    end
  end

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, ui_in, uio_in, 1'b0};

endmodule
