----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    18:33:02 07/30/2013 
-- Design Name: 
-- Module Name:    logibone_wishbone - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
library UNISIM;
use UNISIM.VComponents.all;

library work ;
use work.logi_wishbone_pack.all ;
use work.logi_wishbone_peripherals_pack.all ;

entity logipi_test is
port( OSC_FPGA : in std_logic;

		--onboard
		PB : in std_logic_vector(1 downto 0);
		SW : in std_logic_vector(1 downto 0);
		LED : out std_logic_vector(1 downto 0);	
		
		PMOD3 : inout std_logic_vector(7 downto 0); 
		
		PMOD4 : inout std_logic_vector(7 downto 0); 
		
		PMOD2 : inout std_logic_vector(7 downto 0); 
		
		PMOD1 : inout std_logic_vector(7 downto 0); 
		--i2c
		SYS_SCL, SYS_SDA : inout std_logic ;
		
		--spi
		SYS_SPI_SCK, RP_SPI_CE0N, SYS_SPI_MOSI : in std_logic ;
		SYS_SPI_MISO : out std_logic;
		
		-- sdram
	  SDRAM_CLK   : out   STD_LOGIC;
	  SDRAM_CKE   : out   STD_LOGIC;
	  --SDRAM_CS    : out   STD_LOGIC;
	  SDRAM_nRAS  : out   STD_LOGIC;
	  SDRAM_nCAS  : out   STD_LOGIC;
	  SDRAM_nWE   : out   STD_LOGIC;
	  SDRAM_DQM   : out   STD_LOGIC_VECTOR( 1 downto 0);
	  SDRAM_ADDR  : out   STD_LOGIC_VECTOR (12 downto 0);
	  SDRAM_BA    : out   STD_LOGIC_VECTOR( 1 downto 0);
	  SDRAM_DQ    : inout STD_LOGIC_VECTOR (15 downto 0)
);
end logipi_test;

architecture Behavioral of logipi_test is
	constant sdram_address_width : natural := 24;
   constant sdram_column_bits   : natural := 9;
   constant sdram_startup_cycles: natural := 10100; -- 100us, plus a little more
   constant test_width          : natural := sdram_address_width-1; -- each 32-bit word is two 16-bit SDRAM addresses
   constant cycles_per_refresh  : natural := (64000*100)/8192-1;

COMPONENT SDRAM_Controller
    generic (
      sdram_address_width : natural;
      sdram_column_bits   : natural;
      sdram_startup_cycles: natural;
      cycles_per_refresh  : natural
    );
    PORT(
		clk             : IN std_logic;
		reset           : IN std_logic;

      -- Interface to issue commands
		cmd_ready       : OUT std_logic;
		cmd_enable      : IN  std_logic;
		cmd_wr          : IN  std_logic;
      cmd_address     : in  STD_LOGIC_VECTOR(sdram_address_width-2 downto 0); -- address to read/write
		cmd_byte_enable : IN  std_logic_vector(3 downto 0);
		cmd_data_in     : IN  std_logic_vector(31 downto 0);

      -- Data being read back from SDRAM
		data_out        : OUT std_logic_vector(31 downto 0);
		data_out_ready  : OUT std_logic;

      -- SDRAM signals
		SDRAM_CLK       : OUT   std_logic;
		SDRAM_CKE       : OUT   std_logic;
		SDRAM_CS        : OUT   std_logic;
		SDRAM_RAS       : OUT   std_logic;
		SDRAM_CAS       : OUT   std_logic;
		SDRAM_WE        : OUT   std_logic;
		SDRAM_DQM       : OUT   std_logic_vector(1 downto 0);
		SDRAM_ADDR      : OUT   std_logic_vector(12 downto 0);
		SDRAM_BA        : OUT   std_logic_vector(1 downto 0);
		SDRAM_DATA      : INOUT std_logic_vector(15 downto 0)
		);
	END COMPONENT;
	
	COMPONENT Memory_tester
      Generic (address_width : natural := 4);
      Port ( clk           : in  STD_LOGIC;

           cmd_enable      : out std_logic;
           cmd_wr          : out std_logic;
           cmd_address     : out std_logic_vector(address_width-1 downto 0);
           cmd_byte_enable : out std_logic_vector(3 downto 0);
           cmd_data_in     : out std_logic_vector(31 downto 0);
           cmd_ready       : in  std_logic;

           data_out        : in  std_logic_vector(31 downto 0);
           data_out_ready  : in  std_logic;

           debug           : out std_logic_vector(15 downto 0);

           error_testing   : out STD_LOGIC;
           blink           : out STD_LOGIC);
   END COMPONENT;

	component clock_gen
	port
	(-- Clock in ports
		CLK_IN1           : in     std_logic;
		-- Clock out ports
		CLK_OUT1          : out    std_logic;
		-- Status and control signals
		LOCKED            : out    std_logic
	);
	end component;

	-- syscon
	signal gls_reset, gls_resetn,gls_clk, clock_locked : std_logic ;
	signal clk_100Mhz : std_logic ;

	-- wishbone intercon signals
	signal intercon_wrapper_wbm_address :  std_logic_vector(15 downto 0);
	signal intercon_wrapper_wbm_readdata :  std_logic_vector(15 downto 0);
	signal intercon_wrapper_wbm_writedata :  std_logic_vector(15 downto 0);
	signal intercon_wrapper_wbm_strobe :  std_logic;
	signal intercon_wrapper_wbm_write :  std_logic;
	signal intercon_wrapper_wbm_ack :  std_logic;
	signal intercon_wrapper_wbm_cycle :  std_logic;

	signal intercon_reg0_wbm_address :  std_logic_vector(15 downto 0);
	signal intercon_reg0_wbm_readdata :  std_logic_vector(15 downto 0);
	signal intercon_reg0_wbm_writedata :  std_logic_vector(15 downto 0);
	signal intercon_reg0_wbm_strobe :  std_logic;
	signal intercon_reg0_wbm_write :  std_logic;
	signal intercon_reg0_wbm_ack :  std_logic;
	signal intercon_reg0_wbm_cycle :  std_logic;

	signal intercon_gpio0_wbm_address :  std_logic_vector(15 downto 0);
	signal intercon_gpio0_wbm_readdata :  std_logic_vector(15 downto 0);
	signal intercon_gpio0_wbm_writedata :  std_logic_vector(15 downto 0);
	signal intercon_gpio0_wbm_strobe :  std_logic;
	signal intercon_gpio0_wbm_write :  std_logic;
	signal intercon_gpio0_wbm_ack :  std_logic;
	signal intercon_gpio0_wbm_cycle :  std_logic;
	
	signal intercon_gpio1_wbm_address :  std_logic_vector(15 downto 0);
	signal intercon_gpio1_wbm_readdata :  std_logic_vector(15 downto 0);
	signal intercon_gpio1_wbm_writedata :  std_logic_vector(15 downto 0);
	signal intercon_gpio1_wbm_strobe :  std_logic;
	signal intercon_gpio1_wbm_write :  std_logic;
	signal intercon_gpio1_wbm_ack :  std_logic;
	signal intercon_gpio1_wbm_cycle :  std_logic;
	
	signal intercon_gpio2_wbm_address :  std_logic_vector(15 downto 0);
	signal intercon_gpio2_wbm_readdata :  std_logic_vector(15 downto 0);
	signal intercon_gpio2_wbm_writedata :  std_logic_vector(15 downto 0);
	signal intercon_gpio2_wbm_strobe :  std_logic;
	signal intercon_gpio2_wbm_write :  std_logic;
	signal intercon_gpio2_wbm_ack :  std_logic;
	signal intercon_gpio2_wbm_cycle :  std_logic;
	
	signal intercon_mem0_wbm_address :  std_logic_vector(15 downto 0);
	signal intercon_mem0_wbm_readdata :  std_logic_vector(15 downto 0);
	signal intercon_mem0_wbm_writedata :  std_logic_vector(15 downto 0);
	signal intercon_mem0_wbm_strobe :  std_logic;
	signal intercon_mem0_wbm_write :  std_logic;
	signal intercon_mem0_wbm_ack :  std_logic;
	signal intercon_mem0_wbm_cycle :  std_logic;
	

-- memory tester signals
   signal cmd_address     : std_logic_vector(sdram_address_width-2 downto 0) := (others => '0');
   signal cmd_wr          : std_logic := '1';
   signal cmd_enable      : std_logic;
   signal cmd_byte_enable : std_logic_vector(3 downto 0);
   signal cmd_data_in     : std_logic_vector(31 downto 0);
   signal cmd_ready       : std_logic;
   signal data_out        : std_logic_vector(31 downto 0);
   signal data_out_ready  : std_logic;
	
	-- misc signals
   signal error_refresh   : std_logic;
   signal error_testing   : std_logic;
   signal blink           : std_logic;
   signal debug           : std_logic_vector(15 downto 0);
   signal tester_debug    : std_logic_vector(15 downto 0);
   signal is_idle         : std_logic;
   signal iob_data        : std_logic_vector(15 downto 0);
   signal error_blink     : std_logic;
begin


gls_reset <= (NOT clock_locked); -- system reset while clock not locked
gls_resetn <= NOT gls_reset ; -- for preipherals with active low reset

pll0 : clock_gen
  port map
   (-- Clock in ports
    CLK_IN1 => OSC_FPGA,
    -- Clock out ports
    CLK_OUT1 => clk_100Mhz,
    -- Status and control signals
    LOCKED => clock_locked);

gls_clk <= clk_100Mhz;




mem_interface0 : spi_wishbone_wrapper
		port map(
			-- Global Signals
			gls_reset => gls_reset,
			gls_clk   => gls_clk,
			
			-- SPI signals
			mosi => SYS_SPI_MOSI,
			miso => SYS_SPI_MISO,
			sck => SYS_SPI_SCK,
			ss => RP_SPI_CE0N,
			
			  -- Wishbone interface signals
			wbm_address    => intercon_wrapper_wbm_address,  	-- Address bus
			wbm_readdata   => intercon_wrapper_wbm_readdata,  	-- Data bus for read access
			wbm_writedata 	=> intercon_wrapper_wbm_writedata,  -- Data bus for write access
			wbm_strobe     => intercon_wrapper_wbm_strobe,                      -- Data Strobe
			wbm_write      => intercon_wrapper_wbm_write,                      -- Write access
			wbm_ack        => intercon_wrapper_wbm_ack,                      -- acknowledge
			wbm_cycle      => intercon_wrapper_wbm_cycle                       -- bus cycle in progress
			);



-- Intercon -----------------------------------------------------------
-- will be generated automatically in the future

intercon0 : wishbone_intercon
generic map(memory_map => 
(
"000000000000001X", -- gpio0
"000000000000010X", -- gpio1
"000000000000011X", -- gpio2
"00000000000010XX", -- reg0
"000000000000101X") -- mem0
)
port map(
		gls_reset => gls_reset,
			gls_clk   => gls_clk,
		
		
		wbs_address    => intercon_wrapper_wbm_address,  	-- Address bus
		wbs_readdata   => intercon_wrapper_wbm_readdata,  	-- Data bus for read access
		wbs_writedata 	=> intercon_wrapper_wbm_writedata,  -- Data bus for write access
		wbs_strobe     => intercon_wrapper_wbm_strobe,                      -- Data Strobe
		wbs_write      => intercon_wrapper_wbm_write,                      -- Write access
		wbs_ack        => intercon_wrapper_wbm_ack,                      -- acknowledge
		wbs_cycle      => intercon_wrapper_wbm_cycle,                       -- bus cycle in progress
		
		-- Wishbone master signals
		wbm_address(0) => intercon_gpio0_wbm_address,
		wbm_address(1) => intercon_gpio1_wbm_address,
		wbm_address(2) => intercon_gpio2_wbm_address,
		wbm_address(3) => intercon_reg0_wbm_address,
		wbm_address(4) => intercon_mem0_wbm_address,
		wbm_writedata(0)  => intercon_gpio0_wbm_writedata,
		wbm_writedata(1)  => intercon_gpio1_wbm_writedata,
		wbm_writedata(2)  => intercon_gpio2_wbm_writedata,
		wbm_writedata(3)  => intercon_reg0_wbm_writedata,
		wbm_writedata(4)  => intercon_mem0_wbm_writedata,
		wbm_readdata(0)  => intercon_gpio0_wbm_readdata,
		wbm_readdata(1)  => intercon_gpio1_wbm_readdata,
		wbm_readdata(2)  => intercon_gpio2_wbm_readdata,
		wbm_readdata(3)  => intercon_reg0_wbm_readdata,
		wbm_readdata(4)  => intercon_mem0_wbm_readdata,
		wbm_strobe(0)  => intercon_gpio0_wbm_strobe,
		wbm_strobe(1)  => intercon_gpio1_wbm_strobe,
		wbm_strobe(2)  => intercon_gpio2_wbm_strobe,
		wbm_strobe(3)  => intercon_reg0_wbm_strobe,
		wbm_strobe(4)  => intercon_mem0_wbm_strobe,
		wbm_cycle(0)   => intercon_gpio0_wbm_cycle,
		wbm_cycle(1)   => intercon_gpio1_wbm_cycle,
		wbm_cycle(2)   => intercon_gpio2_wbm_cycle,
		wbm_cycle(3)   => intercon_reg0_wbm_cycle,
		wbm_cycle(4)   => intercon_mem0_wbm_cycle,
		wbm_write(0)   => intercon_gpio0_wbm_write,
		wbm_write(1)   => intercon_gpio1_wbm_write,
		wbm_write(2)   => intercon_gpio2_wbm_write,
		wbm_write(3)   => intercon_reg0_wbm_write,
		wbm_write(4)   => intercon_mem0_wbm_write,
		wbm_ack(0)      => intercon_gpio0_wbm_ack,
		wbm_ack(1)      => intercon_gpio1_wbm_ack,
		wbm_ack(2)      => intercon_gpio2_wbm_ack,
		wbm_ack(3)      => intercon_reg0_wbm_ack,
		wbm_ack(4)      => intercon_mem0_wbm_ack
		
);
									      
										  
-----------------------------------------------------------------------

gpio0 : wishbone_gpio
	 port map
	 (
			gls_reset => gls_reset,
			gls_clk   => gls_clk,


			wbs_address    => intercon_gpio0_wbm_address,  	
			wbs_readdata   => intercon_gpio0_wbm_readdata,  	
			wbs_writedata 	=> intercon_gpio0_wbm_writedata,  
			wbs_strobe     => intercon_gpio0_wbm_strobe,      
			wbs_write      => intercon_gpio0_wbm_write,    
			wbs_ack        => intercon_gpio0_wbm_ack,    
			wbs_cycle      => intercon_gpio0_wbm_cycle, 

			gpio(15 downto 8) => PMOD2, 
			gpio(7 downto 0) => PMOD1
	 );

gpio1 : wishbone_gpio
	 port map
	 (
			gls_reset => gls_reset,
			gls_clk   => gls_clk,


			wbs_address    => intercon_gpio1_wbm_address,  	
			wbs_readdata   => intercon_gpio1_wbm_readdata,  	
			wbs_writedata 	=> intercon_gpio1_wbm_writedata,  
			wbs_strobe     => intercon_gpio1_wbm_strobe,      
			wbs_write      => intercon_gpio1_wbm_write,    
			wbs_ack        => intercon_gpio1_wbm_ack,    
			wbs_cycle      => intercon_gpio1_wbm_cycle, 

			gpio(15 downto 8) => PMOD4, 
			gpio(7 downto 0) => PMOD3
	 );	
	 
gpio2 : wishbone_gpio
	 port map
	 (
			gls_reset => gls_reset,
			gls_clk   => gls_clk,


			wbs_address    => intercon_gpio2_wbm_address,  	
			wbs_readdata   => intercon_gpio2_wbm_readdata,  	
			wbs_writedata 	=> intercon_gpio2_wbm_writedata,  
			wbs_strobe     => intercon_gpio2_wbm_strobe,      
			wbs_write      => intercon_gpio2_wbm_write,    
			wbs_ack        => intercon_gpio2_wbm_ack,    
			wbs_cycle      => intercon_gpio2_wbm_cycle, 
			gpio(15 downto 12) => open,  -- connect to sata port and arduino pins 
			gpio(11 downto 10) => open,
			gpio(9 downto 8) => open, 
			gpio(7 downto 2) => open,  -- connect to sata port and arduino pins 
			gpio(1 downto 0) => open
	 );	
	
reg0 : wishbone_register
	generic map(
		  nb_regs => 3
	 )
	 port map
	 (
			gls_reset => gls_reset,
			gls_clk   => gls_clk,


			wbs_address    => intercon_reg0_wbm_address,  	
			wbs_readdata   => intercon_reg0_wbm_readdata,  	
			wbs_writedata 	=> intercon_reg0_wbm_writedata,  
			wbs_strobe     => intercon_reg0_wbm_strobe,      
			wbs_write      => intercon_reg0_wbm_write,    
			wbs_ack        => intercon_reg0_wbm_ack,    
			wbs_cycle      => intercon_reg0_wbm_cycle, 
			
			reg_in(0) => X"DEAD",
			reg_in(1) => X"BEEF",
			reg_in(2)(15 downto 5) => "00000000000",
			reg_in(2)(4) => error_testing,
			reg_in(2)(3 downto 2) => SW,
			reg_in(2)(1 downto 0) => PB,
			reg_out(0)(15 downto 2) => open,
			reg_out(0)(1 downto 0) => LED,
			reg_out(1) => open,
			reg_out(2) => open
	 );		
	
mem_0 : wishbone_mem
generic map( mem_size => 2048,
			wb_size =>  16,  -- Data port size for wishbone
			wb_addr_size =>  16  -- Data port size for wishbone
		  )
port map(
		 -- Syscon signals
			  gls_reset   => gls_reset ,
			  gls_clk     => gls_clk ,
			  -- Wishbone signals
			  wbs_address      =>  intercon_mem0_wbm_address ,
			  wbs_writedata => intercon_mem0_wbm_writedata,
			  wbs_readdata  => intercon_mem0_wbm_readdata,
			  wbs_strobe    => intercon_mem0_wbm_strobe,
			  wbs_cycle     => intercon_mem0_wbm_cycle,
			  wbs_write     => intercon_mem0_wbm_write,
			  wbs_ack       => intercon_mem0_wbm_ack
		  );
	 

-- LOGIC 

Inst_Memory_tester: Memory_tester GENERIC MAP(address_width => test_width) PORT MAP(
      clk             => gls_clk,

      cmd_address     => cmd_address(test_width-1 downto 0),
      cmd_wr          => cmd_wr,
      cmd_enable      => cmd_enable,
      cmd_ready       => cmd_ready,
      cmd_byte_enable => cmd_byte_enable,
      cmd_data_in     => cmd_data_in,

      data_out        => data_out,
      data_out_ready  => data_out_ready,

      debug           => tester_debug,

      error_testing   => error_testing,
      blink           => blink
   );

Inst_SDRAM_Controller: SDRAM_Controller GENERIC MAP (
      sdram_address_width => sdram_address_width,
      sdram_column_bits   => sdram_column_bits,
      sdram_startup_cycles=> sdram_startup_cycles,
      cycles_per_refresh  => cycles_per_refresh
   ) PORT MAP(
      clk             => gls_clk,
      reset           => '0',

      cmd_address     => cmd_address,
      cmd_wr          => cmd_wr,
      cmd_enable      => cmd_enable,
      cmd_ready       => cmd_ready,
      cmd_byte_enable => cmd_byte_enable,
      cmd_data_in     => cmd_data_in,

      data_out        => data_out,
      data_out_ready  => data_out_ready,

      SDRAM_CLK       => SDRAM_CLK,
      SDRAM_CKE       => SDRAM_CKE,
      SDRAM_CS        => open, -- not connected on new design
      SDRAM_RAS       => SDRAM_nRAS,
      SDRAM_CAS       => SDRAM_nCAS,
      SDRAM_WE        => SDRAM_nWE,
      SDRAM_DQM       => SDRAM_DQM,
      SDRAM_BA        => SDRAM_BA,
      SDRAM_ADDR      => SDRAM_ADDR,
      SDRAM_DATA      => SDRAM_DQ
   );


end Behavioral;
