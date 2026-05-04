----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 23.12.2025 16:09:30
-- Design Name: 
-- Module Name: FPGA_Modulation - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
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
use IEEE.NUMERIC_STD.ALL;


entity FPGA_Modulation is
    Port ( clk_12MHz : in STD_LOGIC;
           reset : in STD_LOGIC;
           
           --Debug
           serial_data_out : out STD_LOGIC; --Raw binary bits, pin 9
           sample_tick_out : out STD_LOGIC;
           pin40_clk : out STD_LOGIC;
           
           --Out to DAC
           spi_mosi : out STD_LOGIC;
           spi_sclk : out STD_LOGIC;
           chip_select : out STD_LOGIC;
           dac_ldac    : out STD_LOGIC
           );
end FPGA_Modulation;



architecture Behavioral of FPGA_Modulation is
    
    --DAC updates every sample_tick so 141,176 times a second, so for a bit rate of 2bps I set a counter to 70,588 samples. 
    constant SAMPLES_PER_BIT : integer := 70588; 
    signal BIT_SAMPLES_COUNTER  : integer range 0 to 70588 := 0; 
    
    --Define message
    constant STR_MSG : string := "Hi";
    constant MSG_LEN : integer := STR_MSG'length*8; --Defines 8 bits per character
    
    -- Coverts string to std:logic_vector (binary
    function to_slv(s: string) return std_logic_vector is
        variable slv : std_logic_vector(s'length * 8 - 1 downto 0);
        variable char_code : integer;
    
    begin
        
        for i in s'range loop
            char_code := character'pos(s(i));
            -- Map string into vector (MSB first for serial transmission)
            --below eg for Hi we do H is 15 to 8 and i is 7 to 0
            slv((s'high - i + 1) * 8 - 1 downto (s'high - i) * 8) := 
                std_logic_vector(to_unsigned(char_code, 8));
        end loop;
        return slv;
    end function;
    
    -- Store message in a register
    signal message_bits : std_logic_vector(MSG_LEN - 1 downto 0) := to_slv(STR_MSG);
    
    --64 element LUT for sinewave
    type LUT_array is array (0 to 63) of integer range -2048 to 2047;
    constant SINE_LUT : lut_array := (
     0,   201,   400,   595,   784,   965,  1138, 1299,  1448,  1583,  1703,  1806,  1892,  1960,
     2009,  2038,  2047,  2038,  2009,  1960,  1892, 1806,  1703,  1583,  1448,  1299,  1138,   965,
     784,   595,   400,   201,     0,  -201,  -400, -595,  -784,  -965, -1138, -1299, -1448, -1583,
     -1703, -1806, -1892, -1960, -2009, -2038, -2048, -2038, -2009, -1960, -1892, -1806, -1703, -1583,
     -1448, -1299, -1138,  -965,  -784,  -595,  -400, -201 );


--    --Message in binary (just Hi for right now)
--    type message_array is array (0 to 15) of std_logic;
--    constant MESSAGE : message_array := ('0', '1', '0', '0', '1', '0', '0', '0', '0', '1', '1', '0', '1', '0', '0', '1');
    
    --Array / Counter signals
    signal clock_divisor : integer range 0 to 85 := 0;
    signal sample_tick : std_logic := '0';
    
    --6 bit counter for the 64 length sine LUT
    signal sine_index : unsigned(5 downto 0) := (others => '0');
--    signal message_index : integer range 0 to 15 := 0;
    signal message_index : integer range 0 to MSG_LEN - 1 := 0;
    
    --SPI Signals
    signal shift_reg : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
    signal bit_count : integer range 0 to 16 := 0;
    signal spi_active : STD_LOGIC := '0';
    signal clock_internal : STD_LOGIC := '0';

begin
    --Hold LDAC low, so DAC updates automatically (can pulse it at the end but this is simpler)
    dac_ldac <= '0';
    --Clock divider, FPGA clock is 12MHz to get to ~141kHz divide it by 84
process(clk_12mhz, reset)
    begin
        if reset = '1' then
            clock_divisor <= 0;
            sample_tick <= '0';
        elsif rising_edge(clk_12mhz) then
            if clock_divisor = 84 then
                clock_divisor <= 0;
                sample_tick <= '1';
            else
                clock_divisor <= clock_divisor + 1;
                sample_tick <= '0';
            end if;
        end if;
    end process;

    sample_tick_out <= sample_tick;
    pin40_clk <= clock_internal; -- Route internal SPI clock to debug pin 40

    -- Counters for Sine LUT and Message
    process(clk_12mhz, reset)
    begin
        if reset = '1' then
            sine_index <= (others => '0');
            message_index <= MSG_LEN - 1; -- Start at MSB
            BIT_SAMPLES_COUNTER <= 0; --Reset bit counter
        elsif rising_edge(clk_12mhz) then
            if sample_tick = '1' then
                sine_index <= sine_index + 1; -- Automatically loops at 63
                
                -- Advance message bit only when 0.5s has passed, increment bit timy only during a sample tick
                if BIT_SAMPLES_COUNTER >= SAMPLES_PER_BIT - 1 then
                    BIT_SAMPLES_COUNTER <= 0;
                
                    --Nested if so the message index (which bit is sent) only increases or loops after 0.5s worth of samples
                    if message_index > 0 then 
                        message_index <= message_index - 1;
                    else
                        message_index <= MSG_LEN - 1; -- LOOP the message continuously
                    end if;
                else
                    BIT_SAMPLES_COUNTER <= BIT_SAMPLES_COUNTER + 1;
                end if;
            end if;
        end if;
    end process;
    
    --Use the serial bit for helping with testing, tells you if the message bit is currently a one or zero
    serial_data_out <= message_bits(message_index);
    
    --DAC configuration 0011 (DAC A, Unbuffered, Gain = 1, Active (not shutdown mode)

    -- Modulation and packet prep
    --process(sine_index, message_index, message_bits)
    process(clk_12MHz)
        variable current_val_lut : signed(11 downto 0);
        variable scaled_output    : signed(11 downto 0);
        variable DAC_output : unsigned(11 downto 0);
        
        --DAC configuration 0011 (DAC A, Unbuffered, Gain = 1, Active (not shutdown mode))
        constant DAC_config : std_logic_vector(3 downto 0) := "0011";
        
    begin
        if rising_edge(clk_12MHz) then
            if sample_tick = '1' then
                --get signed val from LUT
                current_val_lut := to_signed(SINE_LUT(to_integer(sine_index)), 12);
        
                --Check message bit
                if message_bits(message_index) = '1' then
                    -- Kept full amplitude
                    scaled_output := current_val_lut; 
            
            else
            
                -- Shift right twice (divide by 4), if these values are centred around 2048 dividing by 4 changes the offset value
                -- So make sure the LUT is centred around 0. The DC offset should be added before sending to the DAC
                -- shift_right preserves the sign bit (arithmetic shift)
                scaled_output := shift_right(current_val_lut, 2);
            
            end if;
        
                    
            --Add back offset, convert to unsigned
            DAC_output := unsigned(scaled_output + 2048);
            -- -2047 to 2047 but for the DAC I've changed it to 0 to 4095 
            -- -2048 to 2047 means the offset isn't also scaled when we shift it.
            
            --Load the SPI shift register and transmit
                shift_reg <= DAC_config & std_logic_vector(DAC_output);
                spi_active <= '1';
                bit_count <= 16; --Need to update these values to be more general once there a message list.
                
            -- Shift the bits out to the DAC (SPI State Machine)
            elsif spi_active = '1' then
                clock_internal <= not clock_internal; -- Toggle SPI clock
                
                if clock_internal = '1' then -- On rising edge, shift data
                    bit_count <= bit_count - 1;
                    if bit_count = 1 then
                        spi_active <= '0'; -- Stop after 16 bits
                    else
                        shift_reg <= shift_reg(14 downto 0) & '0'; -- Shift left
                    end if;
                end if;
            else
                clock_internal <= '0'; -- Keep clock low when idle
            end if;
        end if;
        
    end process;

    -- SPI signals to physical pins
    chip_select <= not spi_active; -- CS is Active Low
    spi_sclk <= clock_internal when spi_active = '1' else '0';
    spi_mosi <= shift_reg(15) when spi_active = '1' else '0'; -- Output MSB


end Behavioral;

--Currently we send MSB first, seems convenient as people read left to right.
--Weve got a 12 bit number, convert it to a bit stream and output, set the pin on constraints file.
