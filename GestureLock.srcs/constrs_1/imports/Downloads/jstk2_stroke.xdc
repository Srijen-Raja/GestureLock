# ZedBoard constraints for gestureDetection
set_property PACKAGE_PIN Y9  [get_ports clk100]
set_property IOSTANDARD LVCMOS33 [get_ports clk100]
create_clock -period 10.000 -name sys_clk [get_ports clk100]

# Pmod JA (top row), Pmod SPI pinout: 1 = CS, 2 = MOSI, 3 = MISO, 4 = SCK
set_property PACKAGE_PIN Y11  [get_ports ja_cs_n]
set_property PACKAGE_PIN AA11 [get_ports ja_mosi]
set_property PACKAGE_PIN Y10  [get_ports ja_miso]
set_property PACKAGE_PIN AA9  [get_ports ja_sck]
set_property IOSTANDARD LVCMOS33 [get_ports {ja_cs_n ja_mosi ja_miso ja_sck}]

# Centre button as reset (bank 34 runs at VADJ, 1.8 V by default; use LVCMOS33 only if you changed VADJ)
set_property PACKAGE_PIN P16 [get_ports btnc]
set_property IOSTANDARD LVCMOS18 [get_ports btnc]

# LEDs LD0..LD7
set_property PACKAGE_PIN T22 [get_ports {led[0]}]
set_property PACKAGE_PIN T21 [get_ports {led[1]}]
set_property PACKAGE_PIN U22 [get_ports {led[2]}]
set_property PACKAGE_PIN U21 [get_ports {led[3]}]
set_property PACKAGE_PIN V22 [get_ports {led[4]}]
set_property PACKAGE_PIN W22 [get_ports {led[5]}]
set_property PACKAGE_PIN U19 [get_ports {led[6]}]
set_property PACKAGE_PIN U14 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

# ZedBoard On-Board 128x32 OLED Display (SSD1306 on Bank 13)
set_property PACKAGE_PIN AB12 [get_ports oled_sclk]
set_property PACKAGE_PIN AA12 [get_ports oled_sdin]
set_property PACKAGE_PIN U10  [get_ports oled_dc]
set_property PACKAGE_PIN U9   [get_ports oled_res]
set_property PACKAGE_PIN U11  [get_ports oled_vbat]
set_property PACKAGE_PIN U12  [get_ports oled_vdd]
set_property IOSTANDARD LVCMOS33 [get_ports {oled_sclk oled_sdin oled_dc oled_res oled_vbat oled_vdd}]
