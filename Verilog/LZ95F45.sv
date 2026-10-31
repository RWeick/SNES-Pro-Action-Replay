// Synthesizable behavioral replacement for the Datel/Sharp LZ95F45.
// Original-package connections: LZ95F45_Sega.pinmap.csv and
// LZ95F45_SNES.pinmap.csv. See PIN_MAPS.md for wrapper conventions.
//
module lz95f45 (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        personality_snes,
    input  logic        switch_active,
    input  logic        switch_program,
    input  logic [23:0] bus_addr,
    input  logic        bus_read,
    input  logic        bus_write,
    input  logic [15:0] bus_wdata,
    output logic [15:0] bus_rdata,
    output logic        bus_drive,
    output logic        game_read_n,
    output logic        sram_select_n,
    output logic        eeprom_oe_n,
    output logic        top_cart_select_n,
    output logic        middle_cart_select_n,
    output logic        io49
);

  logic       game_mapped;
  logic       programming_unlocked;
  logic       comparator_enabled;
  logic [7:0] snes_regs [0:15];
  logic [15:0] sega_regs [0:15];
  logic [22:0] snes_key;
  logic [22:0] sega_key;
  logic found;

  assign snes_key = {bus_addr[23:16], bus_addr[14:0]};
  assign sega_key = bus_addr[23:1];

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      game_mapped <= !switch_program;
      programming_unlocked <= switch_program;
      comparator_enabled <= 1'b0;
      for (int i = 0; i < 16; i = i + 1) begin
        snes_regs[i] <= 8'h00;
        sega_regs[i] <= 16'h0000;
      end
    end else if (bus_write && programming_unlocked && bus_addr[23:16] == 8'h10) begin
      if (personality_snes) begin
        if (bus_addr[4:0] < 5'h10)
          snes_regs[bus_addr[3:0]] <= bus_wdata[7:0];
        else if (bus_addr[4:0] == 5'h10) begin
          game_mapped <= 1'b1;
          programming_unlocked <= 1'b0;
          comparator_enabled <= 1'b1;
        end
      end else begin
        if (bus_addr[5:1] < 5'h10)
          sega_regs[bus_addr[4:1]] <= bus_wdata;
        else if (bus_addr[5:1] == 5'h10) begin
          game_mapped <= 1'b1;
          programming_unlocked <= 1'b0;
          comparator_enabled <= 1'b1;
        end
      end
    end
  end

  always_comb begin
    bus_rdata = 16'h0000;
    bus_drive = 1'b0;
    found = 1'b0;

    if (bus_read && comparator_enabled && switch_active) begin
      if (personality_snes) begin
        for (int i = 0; i < 4; i = i + 1) begin
          if (!found && {snes_regs[i*4+3][6:0], snes_regs[i*4+2], snes_regs[i*4+1]} == snes_key) begin
            bus_rdata = {8'h00, snes_regs[i*4]};
            bus_drive = 1'b1;
            found = 1'b1;
          end
        end
      end else begin
        for (int i = 0; i < 4; i = i + 1) begin
          if (!found && sega_regs[i*4+2][7:0] == sega_regs[i*4+1][15:8] &&
              {sega_regs[i*4+3][6:0], sega_regs[i*4+1]} == sega_key) begin
            bus_rdata = sega_regs[i*4];
            bus_drive = 1'b1;
            found = 1'b1;
          end
        end
      end
    end

    game_read_n = !(bus_read && game_mapped && !bus_drive);
    if (personality_snes)
      sram_select_n = !(bus_read && (bus_addr[23:16] & 8'hc8) == 8'h00 &&
                        bus_addr[15:0] >= 16'h6000 && bus_addr[15:0] <= 16'h7fff);
    else
      sram_select_n = !(bus_read && bus_addr >= 24'h400000 && bus_addr <= 24'h41ffff);
    eeprom_oe_n = !(bus_read && !game_mapped && bus_addr <= 24'h0fffff);
    top_cart_select_n = 1'b1;
    middle_cart_select_n = personality_snes ? 1'b0 : 1'b1;
    io49 = game_mapped;
  end

endmodule

