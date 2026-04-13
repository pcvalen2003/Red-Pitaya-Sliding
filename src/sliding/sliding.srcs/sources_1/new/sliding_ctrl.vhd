----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 01.04.2026 14:20:35
-- Design Name: 
-- Module Name: sliding_ctrl - Behavioral
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


entity sliding_ctrl is
    Generic( DATA_WIDTH : integer := 16;
             ADC_BITS   : integer := 14

             );
    Port ( clk      : in STD_LOGIC;
           resetn   : in STD_LOGIC;

            -- Control de stream ADC -> DMA
           samples  : in STD_LOGIC_VECTOR(31 downto 0);
           trig     : in STD_LOGIC;

           stream_i_tdata   : in STD_LOGIC_VECTOR(DATA_WIDTH - 1 downto 0);
           stream_i_tvalid  : in STD_LOGIC;
           stream_i_tready  : out STD_LOGIC;           
           stream_o_tdata   : out STD_LOGIC_VECTOR(DATA_WIDTH - 1 downto 0);
           stream_o_tvalid  : out STD_LOGIC;
           stream_o_tlast   : out STD_LOGIC;
           stream_o_tready  : in STD_LOGIC;        

            -- Control por modo deslizante  
           low_trigger      : in std_logic_vector(15 downto 0);
           high_trigger     : in std_logic_vector(15 downto 0);
           sliding_out      : out std_logic;
           sliding_out_n    : out std_logic;

           -- PWM
           sliding_pwm      : in std_logic_vector(1 downto 0);
           PWM_duty         : in std_logic_vector(11 downto 0)

           );
end sliding_ctrl;

architecture Behavioral of sliding_ctrl is
    type STATE_TYPE is (IDLE, RUNNING);
    signal stream_state : STATE_TYPE := IDLE;
    signal counter      : UNSIGNED(31 downto 0) := (others => '0');
    signal trig_old     : STD_LOGIC := '0';

    --signal adc_ch1      : signed(ADC_BITS - 1 downto 0) := (others => '0');
    --signal adc_ch2      : signed(ADC_BITS - 1 downto 0) := (others => '0');
    signal sliding      : std_logic := '0';

    -- Contador de 12 bits para el PWM (f ~ 30 kHz)
    signal pwm_counter  : unsigned(11 downto 0) := (others => '0');
    
begin

-- Máquina de estados para STREAM
    process(clk) begin
        if rising_edge(clk) then
            if resetn = '0' then
                stream_state <= IDLE;
                counter <= (others => '0'); 
                trig_old <= '0';
            else
                
                -- STREAM state transition 
                case stream_state is 
                    when IDLE =>
                        counter <=  (others => '0'); 
                        if trig = '1' and trig_old = '0' then
                            stream_state <= RUNNING;
                        end if;
                        
                    when RUNNING => 
                        if stream_i_tvalid = '1' and stream_o_tready = '1' then
                            counter <= counter + 1;
                            if counter = (unsigned(samples) - 1) then
                                stream_state <= IDLE; 
                            end if;
                        end if;
                end case;
                    
                -- trigger latch
                trig_old <= trig;
                    
            end if;
        end if;
    end process;

    -- data bypass
    stream_o_tdata <= stream_i_tdata;

    -- AXI handshake bypass when running STREAM
    stream_o_tvalid <= stream_i_tvalid when stream_state = RUNNING else '0';
    stream_i_tready <= stream_o_tready when stream_state = RUNNING else '0';

    -- AXI tlast control
    stream_o_tlast <= '1' when (stream_state = RUNNING) and (counter = (unsigned(samples) - 1)) else '0';


-- SLIDING control
    process(clk) --begin
        variable adc1_sample : signed(15 downto 0) := (others => '0');
        variable adc2_sample : signed(15 downto 0) := (others => '0');
    begin
        if(rising_edge(clk)) then
            -- 3 modos de salida
            case sliding_pwm is
                when "00" =>    -- PWM
                    pwm_counter <= pwm_counter + 1;

                    if(pwm_counter < unsigned(PWM_duty)) then
                        sliding <= '1';
                    elsif(pwm_counter > unsigned(PWM_duty)) then
                        sliding <= '0';
                    end if;


                when "01" =>    -- SLIDING CH1
                    if(stream_i_tvalid = '1') then
                        adc1_sample := signed(stream_i_tdata(15 downto 0));
                        --adc2_sample := signed(stream_i_tdata(31 downto 16));

                        if(adc1_sample > signed(high_trigger)) then
                            sliding <= '1';
                        elsif(adc1_sample < signed(low_trigger)) then
                            sliding <= '0';
                        end if;
                    end if;

                when "10" =>    -- SLIDING CH2
                    if(stream_i_tvalid = '1') then
                        adc2_sample := signed(stream_i_tdata(31 downto 16));

                        if(adc2_sample > signed(high_trigger)) then
                            sliding <= '1';
                        elsif(adc2_sample < signed(low_trigger)) then
                            sliding <= '0';
                        end if;
                    end if;

                when "11" =>
                    sliding <= '0';

            end case;


        end if;
    end process;

    sliding_out     <= sliding;
    sliding_out_n   <= not(sliding);

end Behavioral;


