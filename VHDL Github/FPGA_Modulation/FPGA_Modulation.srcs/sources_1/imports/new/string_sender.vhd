----------------------------------------------------------------------------------
-- Module Name: string_sender - Behavioral
--
-- Description:
--   Sends pre-defined byte sequences to the NHD-0420D3Z LCD over RS-232 (TTL).
--
--   rst_i     (button) → sends Clear Screen command to the LCD  (0xFE 0x51)
--   trigger_i (button) → writes three lines to the LCD:
--                          Line 1 (0x00): "Hello!"
--                          Line 2 (0x40): "Uncorrupted message."
--                          Line 3 (0x14): "Corvupt d m.ssag-a"
--
-- NOTE: rst_i no longer hard-resets the FPGA logic. The FPGA state is
--       initialised by power-on defaults (signal initial values). If a true
--       logic reset is needed, add a dedicated port and connect it only to
--       the uart_tx instance.
--
-- ROM layout (single flat array, indexed by r_idx_ptr):
--   [0 - 1 ] Clear screen sequence   (used when rst_i is pressed)
--   [2 - 54] Full display sequence   (used when trigger_i is pressed)
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity string_sender is
    port (
        clk_i     : in  std_logic;  -- System clock (12 MHz on Spartan-7 board)
        rst_i     : in  std_logic;  -- Button: send LCD clear command
        trigger_i : in  std_logic;  -- Button: send the three-line message
        tx_o      : out std_logic   -- UART TX → LCD RX pin (J1 pin 1)
    );
end entity string_sender;

architecture rtl of string_sender is

    -- -------------------------------------------------------------------------
    -- UART TX component
    -- -------------------------------------------------------------------------
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

    -- -------------------------------------------------------------------------
    -- Flat ROM containing every byte that can be sent to the LCD.
    --
    -- Byte map:
    --   [0]      0xFE  ─┐ Clear screen command
    --   [1]      0x51   ┘   (execution time 1.5 ms; UART pace provides margin)
    --
    --   [2]      0xFE  ─┐
    --   [3]      0x45   │ Set cursor → Line 1, Col 1  (pos = 0x00)
    --   [4]      0x00  ─┘
    --   [5..10]        "Hello!"  (6 chars)
    --
    --   [11]     0xFE  ─┐
    --   [12]     0x45   │ Set cursor → Line 2, Col 1  (pos = 0x40)
    --   [13]     0x40  ─┘
    --   [14..33]       "Uncorrupted message."  (20 chars)
    --
    --   [34]     0xFE  ─┐
    --   [35]     0x45   │ Set cursor → Line 3, Col 1  (pos = 0x14)
    --   [36]     0x14  ─┘
    --   [37..54]       "Corvupt d m.ssag-a"  (18 chars)
    --
    -- Total: 55 bytes  (indices 0 - 54)
    -- -------------------------------------------------------------------------
    constant C_ROM_DEPTH : integer := 55;

    type t_rom is array (0 to C_ROM_DEPTH - 1) of std_logic_vector(7 downto 0);

    constant C_ROM : t_rom := (
        -- [0-1] Clear screen
        x"FE", x"51",

        -- [2-4] Set cursor: Line 1 col 1 (0x00)
        x"FE", x"45", x"00",
        -- [5-10] "Hello!"
        x"48",        -- H
        x"65",        -- e
        x"6C",        -- l
        x"6C",        -- l
        x"6F",        -- o
        x"21",        -- !

        -- [11-13] Set cursor: Line 2 col 1 (0x40)
        x"FE", x"45", x"40",
        -- [14-33] "Uncorrupted message."  (exactly 20 chars - fills line 2)
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

        -- [34-36] Set cursor: Line 3 col 1 (0x14)
        x"FE", x"45", x"14",
        -- [37-54] "Corvupt d m.ssag-a"  (18 chars)
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
    --   Clear  : start = 0,  end = 1
    --   Display: start = 2,  end = 54
    constant C_CLEAR_START   : integer := 0;
    constant C_CLEAR_END     : integer := 1;
    constant C_DISPLAY_START : integer := 2;
    constant C_DISPLAY_END   : integer := C_ROM_DEPTH - 1;  -- 54

    -- -------------------------------------------------------------------------
    -- FSM
    -- -------------------------------------------------------------------------
    type t_fsm_state is (IDLE, SEND_BYTE, WAIT_BUSY_HIGH, WAIT_BUSY_LOW);
    signal r_state   : t_fsm_state := IDLE;

    -- Current ROM pointer and the index at which the current sequence ends
    signal r_idx_ptr : integer range 0 to C_ROM_DEPTH - 1 := 0;
    signal r_end_idx : integer range 0 to C_ROM_DEPTH - 1 := 0;

    -- UART interface signals
    signal w_uart_data : std_logic_vector(7 downto 0) := (others => '0');
    signal w_uart_send : std_logic                     := '0';
    signal w_uart_busy : std_logic;

begin

    -- -------------------------------------------------------------------------
    -- UART TX instance
    -- rst_i is NOT forwarded here - power-on initial values handle FPGA state.
    -- -------------------------------------------------------------------------
    inst_uart_tx : uart_tx
        generic map (
            G_CLK_FREQ  => 12_000_000,
            G_BAUD_RATE => 9600
        )
        port map (
            clk_i  => clk_i,
            rst_i  => '0',          -- no hard reset needed; see note in header
            data_i => w_uart_data,
            send_i => w_uart_send,
            tx_o   => tx_o,
            busy_o => w_uart_busy
        );

    -- -------------------------------------------------------------------------
    -- FSM process
    -- -------------------------------------------------------------------------
    p_string_sender : process(clk_i)
    begin
        if rising_edge(clk_i) then

            -- Default: drop send pulse every cycle unless explicitly raised
            w_uart_send <= '0';

            case r_state is

                -- -------------------------------------------------------------
                -- IDLE: wait for either button; ignore new presses while busy
                -- -------------------------------------------------------------
                when IDLE =>
                    if rst_i = '1' then
                        -- Clear screen section of the ROM
                        r_idx_ptr <= C_CLEAR_START;
                        r_end_idx <= C_CLEAR_END;
                        r_state   <= SEND_BYTE;

                    elsif trigger_i = '1' then
                        -- Full display section of the ROM
                        r_idx_ptr <= C_DISPLAY_START;
                        r_end_idx <= C_DISPLAY_END;
                        r_state   <= SEND_BYTE;
                    end if;

                -- -------------------------------------------------------------
                -- SEND_BYTE: put the current ROM byte on the UART data bus and
                --            raise send_i for exactly one clock cycle
                -- -------------------------------------------------------------
                when SEND_BYTE =>
                    w_uart_data <= C_ROM(r_idx_ptr);
                    w_uart_send <= '1';
                    r_state     <= WAIT_BUSY_HIGH;

                -- -------------------------------------------------------------
                -- WAIT_BUSY_HIGH: wait for the UART to acknowledge the byte
                --                 (busy goes high as the start bit begins)
                -- -------------------------------------------------------------
                when WAIT_BUSY_HIGH =>
                    if w_uart_busy = '1' then
                        r_state <= WAIT_BUSY_LOW;
                    end if;

                -- -------------------------------------------------------------
                -- WAIT_BUSY_LOW: wait for the UART to finish transmitting, then
                --                either advance to the next byte or return IDLE
                -- -------------------------------------------------------------
                when WAIT_BUSY_LOW =>
                    if w_uart_busy = '0' then
                        if r_idx_ptr = r_end_idx then
                            -- Sequence complete
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