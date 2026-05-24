----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 10.3.2026 12:53:42
-- Design Name: 
-- Module Name: string_sender - Behavioral
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


-- Sends the specified text to the NHD-0420D3Z LCD using RS-232, remember max 20 characters per line
--
-- Press the right button on the FPGA to clear the screen
-- Press the left button on the FPGA to write from a ROM
-- "Hello!"
-- "Uncorrupted message."
-- "Corvupt d m.ssag-a"


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity string_sender is
    port (
        clk_i     : in  std_logic; 
        rst_i     : in  std_logic;  -- LCD clear 
        trigger_i : in  std_logic;  -- Send the message
        tx_o      : out std_logic
    );
end entity string_sender;

architecture rtl of string_sender is

    component uart_tx is
        generic (
            G_CLK_FREQ  : integer;
            G_BAUD_RATE : integer
        );
        port (
            clk_i  : in  std_logic;
            rst_i  : in  std_logic;
            data_i : in  std_logic_vector(7 downto 0);
            send_i : in  std_logic;
            tx_o   : out std_logic;
            busy_o : out std_logic
        );
    end component;
    
    constant C_ROM_DEPTH : integer := 55;

    type t_rom is array (0 to C_ROM_DEPTH - 1) of std_logic_vector(7 downto 0);

    constant C_ROM : t_rom := (
        -- Clear screen
        x"FE", x"51",

        -- Cursor control, set as line 1 col 1
        x"FE", x"45", x"00",
        
        x"48",        -- H
        x"65",        -- e
        x"6C",        -- l
        x"6C",        -- l
        x"6F",        -- o
        x"21",        -- !

        -- Cursor control, set as line 2 col 1
        x"FE", x"45", x"40",
 
        x"55",        -- U
        x"6E",        -- n
        x"63",        -- c
        x"6F",        -- o
        x"72",        -- r
        x"72",        -- r
        x"75",        -- u
        x"70",        -- p
        x"74",        -- t
        x"65",        -- e
        x"64",        -- d
        x"20",        -- (space)
        x"6D",        -- m
        x"65",        -- e
        x"73",        -- s
        x"73",        -- s
        x"61",        -- a
        x"67",        -- g
        x"65",        -- e
        x"2E",        -- .

        -- Cursor control, set as line 3 col 1
        x"FE", x"45", x"14",
        
        x"43",        -- C
        x"6F",        -- o
        x"72",        -- r
        x"76",        -- v
        x"75",        -- u
        x"70",        -- p
        x"74",        -- t
        x"20",        -- (space)
        x"64",        -- d
        x"20",        -- (space)
        x"6D",        -- m
        x"2E",        -- .
        x"73",        -- s
        x"73",        -- s
        x"61",        -- a
        x"67",        -- g
        x"2D",        -- -
        x"61"         -- a
    );

    -- ROM section boundaries
    -- Clear command 0 to 1
    -- Display commands 2 to 54
    constant C_CLEAR_START   : integer := 0;
    constant C_CLEAR_END     : integer := 1;
    constant C_DISPLAY_START : integer := 2;
    constant C_DISPLAY_END   : integer := C_ROM_DEPTH - 1;  -- 54

    -- FSM
    type t_fsm_state is (IDLE, SEND_BYTE, WAIT_BUSY_HIGH, WAIT_BUSY_LOW);
    signal r_state   : t_fsm_state := IDLE;

    -- Current ROM pointer index and where the current sequence ends
    signal r_idx_ptr : integer range 0 to C_ROM_DEPTH - 1 := 0;
    signal r_end_idx : integer range 0 to C_ROM_DEPTH - 1 := 0;

    -- UART interface
    signal w_uart_data : std_logic_vector(7 downto 0) := (others => '0');
    signal w_uart_send : std_logic                     := '0';
    signal w_uart_busy : std_logic;

begin

    -- Instantiate UART
    inst_uart_tx : uart_tx
        generic map (
            G_CLK_FREQ  => 12_000_000,
            G_BAUD_RATE => 9600
        )
        port map (
            clk_i  => clk_i,
            rst_i  => '0',
            data_i => w_uart_data,
            send_i => w_uart_send,
            tx_o   => tx_o,
            busy_o => w_uart_busy
        );

    -- FSM process
    p_string_sender : process(clk_i)
    begin
        if rising_edge(clk_i) then
        
            w_uart_send <= '0';

            case r_state is

                --Button inputs, only detect when idle
                when IDLE =>
                    if rst_i = '1' then
                        -- Clear screen
                        r_idx_ptr <= C_CLEAR_START;
                        r_end_idx <= C_CLEAR_END;
                        r_state   <= SEND_BYTE;

                    elsif trigger_i = '1' then
                        -- Display text from ROM
                        r_idx_ptr <= C_DISPLAY_START;
                        r_end_idx <= C_DISPLAY_END;
                        r_state   <= SEND_BYTE;
                    end if;

                -- Send current character
                when SEND_BYTE =>
                    w_uart_data <= C_ROM(r_idx_ptr);
                    w_uart_send <= '1'; 
                    r_state     <= WAIT_BUSY_HIGH;

                -- Wait for the UART to acknowledge the byte
                when WAIT_BUSY_HIGH =>
                    if w_uart_busy = '1' then
                        r_state <= WAIT_BUSY_LOW;
                    end if;

                -- Wait for UART to finish transmitting then send next character or idle
                when WAIT_BUSY_LOW =>
                    if w_uart_busy = '0' then
                        if r_idx_ptr = r_end_idx then
                            -- Finished
                            r_state <= IDLE;
                        else
                            r_idx_ptr <= r_idx_ptr + 1;
                            r_state   <= SEND_BYTE;
                        end if;
                    end if;

                when others =>
                    r_state <= IDLE;

            end case;
        end if;
    end process p_string_sender;

end architecture rtl;