----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 10.3.2026 12:53:42
-- Design Name: 
-- Module Name: uart_tx - Behavioral
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

-- UART transmitter with 8 data bits, 1 stop bit

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
    generic (
        G_CLK_FREQ  : integer := 12_000_000;
        G_BAUD_RATE : integer := 9600
    );
    port (
        clk_i  : in  std_logic;                    
        rst_i  : in  std_logic;                    
        data_i : in  std_logic_vector(7 downto 0); -- Ascii char (byte)
        send_i : in  std_logic;                    -- Send pulse
        tx_o   : out std_logic;                    -- UART TX ouput (idles high)
        busy_o : out std_logic                     -- High while transmitting
    );
end entity uart_tx;

architecture rtl of uart_tx is

    constant C_CLKS_PER_BIT : integer := G_CLK_FREQ / G_BAUD_RATE;
    --12,000,000 / 9600 = 5208 cycles/bit

    type t_uart_state is (IDLE, START_BIT, DATA_BITS, STOP_BIT);

    signal r_state   : t_uart_state                    := IDLE;
    signal r_clk_cnt : integer range 0 to C_CLKS_PER_BIT - 1 := 0;
    signal r_bit_idx : integer range 0 to 7            := 0;
    signal r_tx_data : std_logic_vector(7 downto 0)    := (others => '0');
    signal r_tx      : std_logic                       := '1';

begin

    tx_o   <= r_tx;
    busy_o <= '0' when r_state = IDLE else '1';

    p_uart_tx : process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                r_state   <= IDLE;
                r_tx      <= '1';
                r_clk_cnt <= 0;
                r_bit_idx <= 0;

            else
                case r_state is

                    when IDLE =>
                        r_tx <= '1'; -- Idles high
                        if send_i = '1' then
                            r_tx_data <= data_i;
                            r_clk_cnt <= 0;
                            r_state   <= START_BIT;
                        end if;

                    -- Pulls line low for one bit period
                    when START_BIT =>
                        r_tx <= '0';
                        if r_clk_cnt = C_CLKS_PER_BIT - 1 then
                            r_clk_cnt <= 0;
                            r_bit_idx <= 0;
                            r_state   <= DATA_BITS;
                        else
                            r_clk_cnt <= r_clk_cnt + 1;
                        end if;

                    -- Transmits 8 bits LSB-first
                    when DATA_BITS =>
                        r_tx <= r_tx_data(r_bit_idx);
                        if r_clk_cnt = C_CLKS_PER_BIT - 1 then
                            r_clk_cnt <= 0;
                            if r_bit_idx = 7 then
                                r_state <= STOP_BIT;
                            else
                                r_bit_idx <= r_bit_idx + 1;
                            end if;
                        else
                            r_clk_cnt <= r_clk_cnt + 1;
                        end if;

                    -- Pulls line high for one bit period
                    when STOP_BIT =>
                        r_tx <= '1';
                        if r_clk_cnt = C_CLKS_PER_BIT - 1 then
                            r_clk_cnt <= 0;
                            r_state   <= IDLE;
                        else
                            r_clk_cnt <= r_clk_cnt + 1;
                        end if;

                    when others =>
                        r_state <= IDLE;

                end case;
            end if;
        end if;
    end process p_uart_tx;

end architecture rtl;