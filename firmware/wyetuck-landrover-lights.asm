;******************************************************************************
;
;   wyetuck-landrover-lights.asm
;
;   This file contains the business logic to drive the LEDs for Wyetuck's
;   metal Land Rover.
;
;   The hardware is based on PIC16F1825 and TLC5940. No DC/DC converter is used.
;
;   The TLC5940 IREF is programmed with a 1200 Ohms resistor, which means
;   the maximum LED current is 32.55 mA; each adjustment step is 0.517 mA.
;
;   The main beam lights are bicycle lights with 5 LEDs per lamp. Each main 
;   beam light uses two outputs on the TLC5940, one driving 3 LEDs in parallel,
;   the other driving 2 LEDs in parallel. The idea is that the 3 LEDs are 
;   driven with 30 mA and the 2 LEDs with 20 mA, so in effect each LED receives
;   10 mA.
;
;   The following lights are available:
;
;       OUT0    (not used)
;       OUT1    Parking lights left
;       OUT2    Parking lights right
;       OUT3    Main beam 3 LEDs left
;       OUT4    Main beam 2 LEDs left
;       OUT5    Main beam 3 LEDs right
;       OUT6    Main beam 2 LEDs right
;       OUT7    Indicators front left
;       OUT8    Indicators front right   
;       OUT9    (not used)
;       OUT10   (not used)
;       OUT11   Tail/Brake left
;       OUT12   Tail/Brake right   
;       OUT13   Indicators rear left
;       OUT14   Indicators rear right   
;       OUT15   (not used)
;
;******************************************************************************
;
;   Author:         Werner Lane
;   E-mail:         laneboysrc@gmail.com
;
;******************************************************************************
    TITLE       Light tables for Wye Tuck's Land Rover Defender S2 SWB
    RADIX       dec

    #include    hw.tmp
    
    
    GLOBAL Init_lights
    GLOBAL Output_lights

    
    ; Functions and variables imported from utils.asm
    EXTERN Init_TLC5940    
    EXTERN TLC5940_send
    
    EXTERN xl
    EXTERN xh
    EXTERN temp
    EXTERN light_data

    
    ; Functions and variables imported from master.asm
    EXTERN blink_mode
    EXTERN light_mode
    EXTERN drive_mode
    EXTERN setup_mode
    EXTERN startup_mode
    EXTERN servo


; Bitfields in variable blink_mode
#define BLINK_MODE_BLINKFLAG 0          ; Toggles with 1.5 Hz
#define BLINK_MODE_HAZARD 1             ; Hazard lights active
#define BLINK_MODE_INDICATOR_LEFT 2     ; Left indicator active
#define BLINK_MODE_INDICATOR_RIGHT 3    ; Right indicator active

; Bitfields in variable light_mode
#define LIGHT_MODE_PARKING 0        ; Parking lights
#define LIGHT_MODE_MAIN_BEAM 1      ; Low beam

; Bitfields in variable drive_mode
#define DRIVE_MODE_FORWARD 0 
#define DRIVE_MODE_BRAKE 1 
#define DRIVE_MODE_REVERSE 2
#define DRIVE_MODE_BRAKE_ARMED 3
#define DRIVE_MODE_AUTO_BRAKE 4
#define DRIVE_MODE_BRAKE_DISARM 5

; Bitfields in variable setup_mode
#define SETUP_MODE_INIT 0
#define SETUP_MODE_CENTRE 1
#define SETUP_MODE_LEFT 2
#define SETUP_MODE_RIGHT 3
#define SETUP_MODE_STEERING_REVERSE 4
#define SETUP_MODE_NEXT 6
#define SETUP_MODE_CANCEL 7

; Bitfields in variable startup_mode
; Note: the higher 4 bits are used so we can simply "or" it with ch3
; and send it to the slave
#define STARTUP_MODE_NEUTRAL 4      ; Waiting before reading ST/TH neutral

#define LED_PARKING_L 1    
#define LED_PARKING_R 2    
#define LED_MAIN_BEAM_3_L 3
#define LED_MAIN_BEAM_2_L 4
#define LED_MAIN_BEAM_3_R 5
#define LED_MAIN_BEAM_2_R 6
#define LED_INDICATOR_F_L 7    
#define LED_INDICATOR_F_R 8 
#define LED_TAIL_BRAKE_L 11    
#define LED_TAIL_BRAKE_R 12    
#define LED_INDICATOR_R_L 13    
#define LED_INDICATOR_R_R 14

; Since gpasm is not able to use 0.517 we need to calculate with micro-Amps
#define uA_PER_STEP 517

#define VAL_PARKING (5 * 1000 / uA_PER_STEP)
#define VAL_MAIN_BEAM_3 (30 * 1000 / uA_PER_STEP)
#define VAL_MAIN_BEAM_2 (20 * 1000 / uA_PER_STEP)
#define VAL_TAIL (2 * 1000 / uA_PER_STEP)
#define VAL_BRAKE (20 * 1000 / uA_PER_STEP)
#define VAL_INDICATOR_FRONT (20 * 1000 / uA_PER_STEP)
#define VAL_INDICATOR_REAR (20 * 1000 / uA_PER_STEP)

  
;******************************************************************************
; Relocatable variables section
;******************************************************************************
.data_lights UDATA
dummy   res 2

;============================================================================
;============================================================================
;============================================================================
.lights CODE


;******************************************************************************
; Init_lights
;******************************************************************************
Init_lights
    call    Init_TLC5940
    call    Clear_light_data

    ; Light up both front indicators until we receive the first command 
    ; from the UART
    BANKSEL light_data
    movlw   VAL_INDICATOR_FRONT
    movwf   light_data + LED_INDICATOR_F_R
    movwf   light_data + LED_INDICATOR_F_L
    call    TLC5940_send
    return


;******************************************************************************
; Output_lights
;******************************************************************************
Output_lights
    call    Clear_light_data

    BANKSEL startup_mode
    movf    startup_mode, f
    bnz     output_lights_startup

    movf    setup_mode, f
    bnz     output_lights_setup

    ; Normal mode here
    BANKSEL light_mode
    movfw   light_mode
    movwf   temp
    btfsc   temp, LIGHT_MODE_PARKING
    call    output_lights_parking
    btfsc   temp, LIGHT_MODE_PARKING
    call    output_lights_tail
    btfsc   temp, LIGHT_MODE_MAIN_BEAM
    call    output_lights_main_beam

    BANKSEL drive_mode
    movfw   drive_mode
    movwf   temp
    btfsc   temp, DRIVE_MODE_BRAKE
    call    output_lights_brake


    BANKSEL blink_mode
    btfss   blink_mode, BLINK_MODE_BLINKFLAG
    goto    output_lights_end
    
    movfw   blink_mode
    movwf   temp
    btfsc   temp, BLINK_MODE_HAZARD
    call    output_lights_indicator_left
    btfsc   temp, BLINK_MODE_HAZARD
    call    output_lights_indicator_right
    btfsc   temp, BLINK_MODE_INDICATOR_LEFT
    call    output_lights_indicator_left
    btfsc   temp, BLINK_MODE_INDICATOR_RIGHT
    call    output_lights_indicator_right
    
output_lights_end
    goto    output_lights_execute    


output_lights_startup
    btfss   startup_mode, STARTUP_MODE_NEUTRAL
    return
    
    movlw   VAL_MAIN_BEAM_2
    movwf   light_data + LED_MAIN_BEAM_2_L
    movwf   light_data + LED_MAIN_BEAM_2_R
    goto    output_lights_execute    


output_lights_setup
    btfsc   setup_mode, SETUP_MODE_CENTRE
    goto    output_lights_setup_centre
    btfsc   setup_mode, SETUP_MODE_LEFT
    goto    output_lights_setup_right
    btfsc   setup_mode, SETUP_MODE_RIGHT
    goto    output_lights_setup_right
    btfss   setup_mode, SETUP_MODE_STEERING_REVERSE 
    goto    output_lights_execute    

    ; Do something for steering reverse
    call    output_lights_indicator_left
    goto    output_lights_execute    

output_lights_setup_centre
    return

output_lights_setup_left
    return
    
output_lights_setup_right
    return

output_lights_execute    
    call    TLC5940_send
    return


output_lights_parking
    BANKSEL light_data
    movlw   VAL_PARKING
    movwf   light_data + LED_PARKING_L
    movwf   light_data + LED_PARKING_R
    return
    
output_lights_main_beam
    BANKSEL light_data
    movlw   VAL_MAIN_BEAM_2
    movwf   light_data + LED_MAIN_BEAM_2_L
    movwf   light_data + LED_MAIN_BEAM_2_R
    movlw   VAL_MAIN_BEAM_3
    movwf   light_data + LED_MAIN_BEAM_3_L
    movwf   light_data + LED_MAIN_BEAM_3_R
    return
    
output_lights_tail
    BANKSEL light_data
    movlw   VAL_TAIL
    movwf   light_data + LED_TAIL_BRAKE_L
    movwf   light_data + LED_TAIL_BRAKE_R
    return
    
output_lights_brake
    BANKSEL light_data
    movlw   VAL_BRAKE
    movwf   light_data + LED_TAIL_BRAKE_L
    movwf   light_data + LED_TAIL_BRAKE_R
    return
    
output_lights_indicator_left
    BANKSEL light_data
    movlw   VAL_INDICATOR_FRONT
    movwf   light_data + LED_INDICATOR_F_L
    movlw   VAL_INDICATOR_REAR
    movwf   light_data + LED_INDICATOR_R_L
    return
    
output_lights_indicator_right
    BANKSEL light_data
    movlw   VAL_INDICATOR_FRONT
    movwf   light_data + LED_INDICATOR_F_R
    movlw   VAL_INDICATOR_REAR
    movwf   light_data + LED_INDICATOR_R_R
    return


;******************************************************************************
; Clear_light_data
;
; Clear all light_data variables, i.e. by default all lights are off.
;******************************************************************************
Clear_light_data
    movlw   HIGH light_data
    movwf   FSR0H
    movlw   LOW light_data
    movwf   FSR0L
    movlw   16          ; There are 16 bytes in light_data
    movwf   temp
    clrw   
clear_light_data_loop
    movwi   FSR0++    
    decfsz  temp, f
    goto    clear_light_data_loop
    return
    
    END
