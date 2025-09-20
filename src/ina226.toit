
// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.   This also file includes derivative 
// work from other authors and sources.  See accompanying documentation.

import log
import binary
import serial.device as serial
import serial.registers as registers

// $DEFAULT-I2C-ADDRESS is 64 (0x40) with jumper defaults.
// Valid address values: 64 to 79 - See datasheet table 6-2
DEFAULT-I2C-ADDRESS                      ::= 0x40

// Helpful constants to be used by users during configuration
INA226-MODE-POWER-DOWN                          ::= 0x00
INA226-MODE-TRIGGERED                           ::= 0x03
INA226-MODE-CONTINUOUS                          ::= 0x07

// Alert Types that can set off the alert register and/or alert pin.
INA226-ALERT-SHUNT-OVER-VOLTAGE                 ::= 0x8000
INA226-ALERT-SHUNT-UNDER-VOLTAGE                ::= 0x4000
INA226-ALERT-BUS-OVER-VOLTAGE                   ::= 0x2000
INA226-ALERT-BUS-UNDER-VOLTAGE                  ::= 0x1000
INA226-ALERT-POWER-OVER                         ::= 0x0800
INA226-ALERT-CURRENT-OVER                       ::= 0xFFFE
INA226-ALERT-CURRENT-UNDER                      ::= 0xFFFF
INA226-ALERT-CONVERSION-READY                   ::= 0x0400

// AVERAGE SAMPLE SIZE ENUM 
INA226-AVERAGE-1-SAMPLE                         ::= 0x0000 // Chip Default
INA226-AVERAGE-4-SAMPLES                        ::= 0x0001
INA226-AVERAGE-16-SAMPLES                       ::= 0x0002
INA226-AVERAGE-64-SAMPLES                       ::= 0x0003
INA226-AVERAGE-128-SAMPLES                      ::= 0x0004
INA226-AVERAGE-256-SAMPLES                      ::= 0x0005
INA226-AVERAGE-512-SAMPLES                      ::= 0x0006
INA226-AVERAGE-1024-SAMPLES                     ::= 0x0007

// BVCT and SVCT conversion timing ENUM
INA226-TIMING-140-US                            ::= 0x0000
INA226-TIMING-204-US                            ::= 0x0001
INA226-TIMING-332-US                            ::= 0x0002
INA226-TIMING-588-US                            ::= 0x0003
INA226-TIMING-1100-US                           ::= 0x0004 // Default
INA226-TIMING-2100-US                           ::= 0x0005
INA226-TIMING-4200-US                           ::= 0x0006
INA226-TIMING-8300-US                           ::= 0x0007

/**
Toit Driver Library for an INA226 module, DC Shunt current and power sensor.  Several common modules exist based on the TI INA226 chip, atasheet: https://www.ti.com/lit/ds/symlink/ina226.pdf  One example: https://esphome.io/components/sensor/ina226/.  There are others with different feature sets and may be partially code compatible.

Examples in the `examples` folder:
- Use Case 1: Simple Continuous Measurement 
- Use Case 2: Adjusting the Shunt Resistor to measure (for example, smaller) currents
- Use Case 3: Balancing Update Speed vs. Accuracy in a Battery-Powered Scenario
*/

class Ina226:
  // Core Register Addresses
  static REGISTER-CONFIG_                ::= 0x00  //RW  // All-register reset, shunt voltage and bus voltage ADC conversion times and averaging, operating mode.
  static REGISTER-SHUNT-VOLTAGE_         ::= 0x01  //R   // Shunt voltage measurement data
  static REGISTER-BUS-VOLTAGE_           ::= 0x02  //R   // Bus voltage measurement data
  static REGISTER-LOAD-POWER_            ::= 0x03  //R   // value of the calculated power being delivered to the load
  static REGISTER-SHUNT-CURRENT_         ::= 0x04  //R   // value of the calculated current flowing through the shunt resistor
  static REGISTER-CALIBRATION_           ::= 0x05  //RW  // Sets full-scale range and LSB of current and power measurements. Overall system calibration.
  static REGISTER-MASK-ENABLE_           ::= 0x06  //RW  // Alert configuration and Conversion Ready flag
  static REGISTER-ALERT-LIMIT_           ::= 0x07  //RW  // limit value to compare to the selected Alert function
  static REGISTER-MANUF-ID_              ::= 0xFE  //R   // Contains unique manufacturer identification number.
  static REGISTER-DIE-ID_                ::= 0xFF  //R   // Contains unique die identification number

  // Die & Manufacturer Info Masks
  static DIE-ID-RID-MASK_                ::= 0x000F // Masks its part of the REGISTER-DIE-ID Register
  static DIE-ID-DID-MASK_                ::= 0xFFF0 // Masks its part of the REGISTER-DIE-ID Register

  // Configuration Bitmasks
  static CONF-RESET-MASK_                ::= 0x8000
  static CONF-AVERAGE-MASK_              ::= 0x0E00
  static CONF-AVERAGE-OFFSET_            ::= 9
  static CONF-BUSVC-MASK_                ::= 0x01C0
  static CONF-BUSVC-OFFSET_              ::= 6
  static CONF-SHUNTVC-MASK_              ::= 0x0038
  static CONF-SHUNTVC-OFFSET_            ::= 3
  static CONF-MODE-MASK_                 ::= 0x0007
  static CONF-MODE-OFFSET_               ::= 0

  //  Get Alert Flag
  static ALERT-CONVERSION-READY-FLAG_             ::= 0x0008
  static ALERT-CONVERSION-READY-OFFSET_           ::= 3
  static ALERT-CONVERSION-READY-LENGTH_           ::= 1
  static ALERT-FUNCTION-FLAG_                     ::= 0x0010
  static ALERT-FUNCTION-OFFSET_                   ::= 4
  static ALERT-FUNCTION-LENGTH_                   ::= 1
  static ALERT-MATH-OVERFLOW-FLAG_                ::= 0x0004
  static ALERT-MATH-OVERFLOW-OFFSET_              ::= 2
  static ALERT-MATH-OVERFLOW-LENGTH_              ::= 1
  static ALERT-PIN-POLARITY-BIT_                  ::= 0x0002
  static ALERT-PIN-POLARITY-OFFSET_               ::= 1
  static ALERT-PIN-POLARITY-LENGTH_               ::= 1
  static ALERT-LATCH-ENABLE-BIT_                  ::= 0x0001
  static ALERT-LATCH-ENABLE-OFFSET_               ::= 0
  static ALERT-LATCH-ENABLE-LENGTH_               ::= 1
  static CONVERSION-READY-BIT_                    ::= 0x0800
  static CONVERSION-READY-OFFSET_                 ::= 10
  static CONVERSION-READY-LENGTH_                 ::= 1

  static INTERNAL_SCALING_VALUE_/float            ::= 0.00512
  static ADC-FULL-SCALE-SHUNT-VOLTAGE-LIMIT/float ::= 0.08192  // volts

  // 'Measure Mode' (includes OFF)
  static MODE-POWER-DOWN_                         ::= 0x00
  static MODE-TRIGGERED_                          ::= 0x03
  static MODE-CONTINUOUS_                         ::= 0x07

  static INA226-DEVICE-ID                         ::= 0x0226

  reg_/registers.Registers                        := ?  
  current-divider-ma_/float                       := 0.0
  power-multiplier-mw_/float                      := 0.0
  last-measure-mode_/int                          := INA226-MODE-CONTINUOUS
  current-LSB_/float                              := 0.0
  shunt-resistor_/float                           := 0.0
  current-range_/float                            := 0.0
  correction-factor-a_/float                      := 0.0
  max-current_/float                              := 0.0
  logger_/log.Logger                              := ?

  constructor dev/serial.Device --logger/log.Logger=(log.default.with-name "ina226"):
    logger_ = logger
    reg_ = dev.registers

    if (device-identification != INA226-DEVICE-ID): 
      logger_.info "Device is NOT an INA226 (0x$(%04x INA226-DEVICE-ID) [Device ID:0x$(%04x device-identification)]) "
      logger_.info "Device is man-id=0x$(%04x manufacturer-id) dev-id=0x$(%04x device-identification) rev=0x$(%04x device-revision)"
      throw "Device is not an INA226."

    initialise-device_

  // CONFIGURATION FUNCTIONS

  /** Initial Device Configuration - Starts:
      - Assuming the default shunt resistor is installed R100 (0.1 Ohm).
      - Starts in Continuous Mode.
      */
  initialise-device_ -> none:
    // Maybe not reuiqred but the manual suggests you should do it
    reset_

    // NOTE:  Found an error by factor 100 and couldn't figure this out in any way
    //        left this hack (feature) in to allow a correction factor for values 
    //        match up with voltmeter. Before using the library, verify this value
    //        matches measurements IRL. 
    correction-factor-a_ = 1.0

    // NOTE:  The Current Register (04h) and Power Register (03h) default to '0' 
    //        because the Calibration register defaults to '0', yielding zero current
    //        and power values until the Calibration register is programmed.
    //        write initial calibration value, initial average value and conversion 
    //        time.  This is not done here to ensure shunt-resistor does this.
    // calibration-value --value=DEFAULT-CALIBRATION-VALUE

    // Initialise Default sampling, conversion timing, and measuring mode
    sampling-rate --rate=INA226-AVERAGE-1-SAMPLE
    conversion-time --time=INA226-TIMING-1100-US
    measure-mode --mode=MODE-CONTINUOUS_

    // Set Defaults for Resistor Range
    // NOTE:  There appears to have been originally two constants/values for 'current range'
    //        MA_400 and MA_800 - I tested these and found that my voltmeter agreed when
    //        current range is set to 0.800a - eg 800ma.
    shunt-resistor --resistor=0.100 // --current-range=0.8
    
    // NOTE:  Performing a single measurement here assists with accuracy for initial measurements.
    single-measurement
    wait-until-conversion-completed
    
    // NOTE:  Using this helper function, the actual values used in the calculations are visible
    //print-diagnostics

  /** reset_: Reset Device
      NOTE:  Setting bit 16 resets the device, afterwards the bit self-clears. */
  reset_ -> none:
    old-value := reg_.read-u16-be REGISTER-CONFIG_
    new-value := old-value | CONF-RESET-MASK_
    reg_.write-u16-be REGISTER-CONFIG_ new-value
    sleep --ms=(estimated-conversion-time --ms)
    after-value := reg_.read-u16-be REGISTER-CONFIG_
    logger_.info "reset_: 0x$(%02x old-value) [to 0x$(%02x new-value)] - after reset 0x$(%02x after-value)"

  /** calibration-value: Get Calibration Value */
  calibration-value -> int:
    return reg_.read-u16-be REGISTER-CALIBRATION_

  /** calibration-value --value: Set Calibration Value - outright */
  calibration-value --value/int -> none:
    //assert: ((value >= 1500) and (value <= 3000))  // sanity check
    old-value := reg_.read-u16-be REGISTER-CALIBRATION_
    reg_.write-u16-be REGISTER-CALIBRATION_ value
    logger_.debug "calibration-value: changed from $(old-value) to $(value)"

  /** calibration-value --factor: Set Calibration Value - by a factor */
  calibration-value --factor/int -> none:
    oldCalibrationValue := calibration-value
    newCalibrationValue := oldCalibrationValue * factor
    calibration-value --value=newCalibrationValue
    logger_.debug "caibration-value: factor $(factor) adjusts from $(oldCalibrationValue) to $(newCalibrationValue)"

  /** sampling-rate --rate: Adjust Sampling Rate for measurements.  
      Requires one of the values in the enum. */
  sampling-rate --rate/int -> none:
    oldMask/int  := reg_.read-u16-be REGISTER-CONFIG_
    newMask/int  := oldMask
    newMask      &= ~(CONF-AVERAGE-MASK_)
    newMask      |= (rate << 9)
    reg_.write-u16-be REGISTER-CONFIG_ newMask
    logger_.debug "sampling-rate: set from 0x$(%02x oldMask) to 0x$(%02x newMask)"

  /** sampling-rate --code: Retrieve current sampling rate
      This is the register code/enum value, not a rate of its own, needs conversion with $sampling-rate --count={enum} */
  sampling-rate --code -> int:
    return ((reg_.read-u16-be REGISTER-CONFIG_ & CONF-AVERAGE-MASK_) >> 9)

  /** sampling-rate --count: Return human readable sampling count number */
  sampling-rate --count -> int:
    return sampling-rate-from-enum --code=(sampling-rate --code)

  /** Set Conversion Time
      NOTE:  The conversion time setting tells the ADC how long to spend on a single measurement of either the shunt voltage or the bus voltage.
      - Longer time = more samples averaged inside = less noise, higher resolution.
      - Shorter time = fewer samples = faster updates, but noisier.
      NOTE:  Both Bus and Shunt have separate conversion times
      - Bus voltage = the “supply” or “load node” you’re monitoring.
      - Shunt voltage = the tiny drop across your shunt resistor.
      - Current isn’t measured directly — it’s computed later from Vshunt/Rshunt */

  /** conversion-time --bus: Sets conversion-time for bus only */  
  conversion-time --bus/int -> none:
    oldMask/int := reg_.read-u16-be REGISTER-CONFIG_
    newMask/int := oldMask
    newMask     &= ~CONF-BUSVC-MASK_
    newMask     |= (bus << CONF-BUSVC-OFFSET_)
    reg_.write-u16-be REGISTER-CONFIG_ newMask
    logger_.debug "conversion-time: --bus set from 0x$(%02x oldMask) to 0x$(%02x newMask)"

  /** conversion-time --shunt: Sets conversion-time for shunt only */  
  conversion-time --shunt/int -> none:
    oldMask/int := reg_.read-u16-be REGISTER-CONFIG_
    newMask/int := oldMask
    newMask     &= ~CONF-SHUNTVC-MASK_
    newMask     |= (shunt << CONF-SHUNTVC-OFFSET_)
    reg_.write-u16-be REGISTER-CONFIG_ newMask
    logger_.debug "conversion-time: --shunt set from 0x$(%02x oldMask) to 0x$(%02x newMask)"

  /** conversion-time --time: Sets conversion-time for both to the same when only one value is given */
  conversion-time --time/int -> none:
    conversion-time --shunt=time
    conversion-time --bus=time

  /** measure-mode: Sets Measure Mode
      Keeps track of last measure mode set, in a global. Ensures device comes back on into the same mode using 'PowerOn' */
  measure-mode --mode/int -> none:
    oldMask/int := reg_.read-u16-be REGISTER-CONFIG_
    newMask/int := oldMask
    newMask     &= ~(CONF-MODE-MASK_)
    newMask     |= mode  //low value, no left shift offset
    reg_.write-u16-be REGISTER-CONFIG_ newMask
    // logger_.debug "measure-mode set from 0x$(%02x oldMask) to 0x$(%02x newMask)"
    if (mode != MODE-POWER-DOWN_): last-measure-mode_ = mode

  /** shunt-resistor --resistor --max-current: Set resistor and current range, independently 
      Resistor value in ohm, Current range in A */
  shunt-resistor --resistor/float --max-current/float -> none:
    shunt-resistor_        = resistor                                              // Cache to class-wide for later use
    max-current_           = max-current                                           // Cache to class-wide for later use
    current-LSB_           = (max-current_ / 32768.0)                              // Amps per bit (LSB)
    logger_.debug "shunt-resistor: current per bit = $(current-LSB_)A"
    calibrationValue      := INTERNAL_SCALING_VALUE_ / (current-LSB_ * resistor)
    logger_.debug "shunt-resistor: calibration value becomes = $(calibrationValue) $((calibrationValue).round)[rounded]"
    calibration-value --value=(calibrationValue).round
    current-divider-ma_    = 0.001 / current-LSB_
    power-multiplier-mw_   = 1000.0 * 25.0 * current-LSB_
    logger_.debug "shunt-resistor: (32767 * current-LSB_)=$(32767 * current-LSB_) compared to $(max-current_)"
    // Check manually if necessary: assert: (32767 * current-LSB_ >= max-current_)

  /** shunt-resistor --resistor: Set resistor range manually */
  shunt-resistor --resistor/float -> none:
    // Current range - max measurable current given the shunt resistor
    current-max/float := ADC-FULL-SCALE-SHUNT-VOLTAGE-LIMIT/resistor
    shunt-resistor --resistor=resistor --max-current=current-max

  // MEASUREMENT FUNCTIONS

  /** shunt-current --amps: Return shunt current in amps */ 
  shunt-current --amps -> float:
    register   := reg_.read-i16-be REGISTER-SHUNT-CURRENT_
    return (register * current-LSB_ * correction-factor-a_)

  /** shunt-current --milliamps: Return shunt current in milliamps */   
  shunt-current --milliamps -> float:   return ((shunt-current --amps) * 1000.0)

  /** shunt-current --microamps: Return shunt current in milliamps */   
  shunt-current --microamps -> float:   return ((shunt-current --amps) * 1000.0 * 1000.0)

  /** shunt-voltage --volts: Return shunt voltage in volts */   
  shunt-voltage --volts -> float:
    register := reg_.read-i16-be REGISTER-SHUNT-VOLTAGE_
    return (register * 0.0000025)

  /** shunt-voltage --millivolts: Return shunt voltage in millivolts */  
  shunt-voltage --millivolts -> float:  return (shunt-voltage --volts) * 1000.0
  
  /** supply-voltage --volts: Upstream voltage, before the shunt (IN+).
      This is the rail straight from the power source, minus any drop across the shunt. Since INA226 doesn’t have a dedicated pin for this, it can be reconstructed by: Vsupply = Vbus + Vshunt.   i.e. add the measured bus voltage (load side) and the measured shunt voltage. */
  supply-voltage --volts -> float:
    return ((bus-voltage --volts) + (shunt-voltage --volts))

  /** supply-voltage --millivolts: see $supply-voltage --volts. */
  supply-voltage --millivolts -> float:
    return (supply-voltage --volts) * 1000.0

  /** bus-voltage --volts: whatever is wired to the VBUS pin.  
      On most breakout boards, VBUS is tied internally to IN− (the low side of the shunt). So in practice, “bus voltage” usually means the voltage at the load side of the shunt.  This is what the load actually sees as its supply rail. */
  bus-voltage --volts -> float:
    register := reg_.read-i16-be REGISTER-BUS-VOLTAGE_
    return (register * 0.00125)
  
  /** bus-voltage: same as $bus-voltage --volts but in millivolts */
  bus-voltage  --millivolts -> float:
    return (bus-voltage --volts) * 1000.0
  
  /** load-power: Watts used by the load
      Calculated using the cached multiplier [pwrMultiplier_mW_ = 1000 * 25 * current-LSB_] */
  load-power --milliwatts -> float:
    register := reg_.read-u16-be REGISTER-LOAD-POWER_
    return (register * power-multiplier-mw_).to-float

  /** bus-voltage: same as $load-power --watts but in milliwatts */
  load-power --watts -> float:
    return (load-power --milliwatts) / 1000.0

  // Aliases to help with user understanding of terms
  load-voltage --volts -> float:       return (bus-voltage --volts)
  load-voltage --millivolts -> float:  return (bus-voltage --millivolts)
  load-current --amps -> float:        return (shunt-current --amps)
  load-current --milliamps -> float:   return (shunt-current --milliamps)
  load-current --microamps -> float:   return (shunt-current --microamps)

  /** power-down: simple aliase for enabling device if disabled */
  power-down -> none:
    measure-mode --mode=MODE-POWER-DOWN_

  /** power-up: simple aliase for enabling the device if disabled */
  power-up -> none:
    measure-mode --mode=last-measure-mode_
    sleep --ms=(estimated-conversion-time --ms)

  /** busy: Returns true if conversion is still ongoing */
  busy -> bool:
    register/int := reg_.read-u16-be REGISTER-MASK-ENABLE_            // clears CNVR (Conversion Ready) Flag
    val/bool     :=  ((register & ALERT-CONVERSION-READY-FLAG_) == 0)
    return val

  /** wait-until-conversion-completed: waits until conversion is completed */
  wait-until-conversion-completed -> none:
    maxWaitTimeMs/int   := estimated-conversion-time --ms
    curWaitTimeMs/int   := 0
    sleepIntervalMs/int := 50
    while busy:                                                        // checks if sampling is completed
        sleep --ms=sleepIntervalMs
        curWaitTimeMs += sleepIntervalMs
        if curWaitTimeMs >= maxWaitTimeMs:
          logger_.debug "waitUntilConversionCompleted: maxWaitTime $(maxWaitTimeMs)ms exceeded - breaking"
          break

  /** single-measurement: initiate a single measurement without waiting for completion */
  single-measurement -> none:
    single-measurement --nowait
    wait-until-conversion-completed
  
  /** single-measurement: perform a single conversion - without waiting */
  single-measurement --nowait -> none:
    maskRegister/int   := reg_.read-u16-be REGISTER-MASK-ENABLE_      // clears CNVR (Conversion Ready) Flag
    confRegister/int   := reg_.read-u16-be REGISTER-CONFIG_     
    reg_.write-u16-be REGISTER-CONFIG_ confRegister                   // Starts conversion

  /** ALERT FUNCTIONS  */

  /** set-alert: configures the various alert types
      Requires a value from the alert type enum.  If multiple functions are enabled the highest significant bit position Alert Function (D15-D11) takes priority and responds to the Alert Limit Register.  ie. only one alert of one type can be configured simultaneously.  Whatever is in the alert value (register) at that time, is then the alert trigger value. */
  set-alert --type/int --limit/float -> none:
    alertLimit/float := 0.0

    if type == INA226-ALERT-SHUNT-OVER-VOLTAGE:
      alertLimit = limit * 400          
    else if type == INA226-ALERT-SHUNT-UNDER-VOLTAGE:
      alertLimit = limit * 400
    else if type == INA226-ALERT-CURRENT-OVER:
      type = INA226-ALERT-SHUNT-OVER-VOLTAGE
      alertLimit = limit * 2048 * current-divider-ma_ / (calibration-value).to-float
    else if type == INA226-ALERT-CURRENT-UNDER:
      type = INA226-ALERT-SHUNT-UNDER-VOLTAGE
      alertLimit = limit * 2048 * current-divider-ma_ / (calibration-value).to-float
    else if type == INA226-ALERT-BUS-OVER-VOLTAGE:
      alertLimit = limit * 800
    else if type == INA226-ALERT-BUS-UNDER-VOLTAGE:
      alertLimit = limit * 800
    else if type == INA226-ALERT-POWER-OVER:
      alertLimit = limit / power-multiplier-mw_
    else:
      logger_.debug "set-alert: unexpected alert type"
      throw "set-alert: unexpected alert type"
    
    // Set Alert Type Flag
    oldMask/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    newMask/int := oldMask
    newMask     &= ~(0xF800)    // clear old alert values (bits D11 to D15) - only one alert allowed at once
    newMask     |= type         // already bit shifted in the mask constants!
    reg_.write-u16-be REGISTER-MASK-ENABLE_ newMask
    logger_.debug "set-alert: mask $(bits-16 oldMask) to $(bits-16 newMask)"

    // Set Alert Limit Value
    reg_.write-u16-be REGISTER-ALERT-LIMIT_ (alertLimit).to-int
    logger_.debug "set-alert: alert limit set to $(alertLimit)"

  /** alert-latch: "Latching"
      When the Alert Latch Enable bit is set to Transparent mode, the Alert pin and Flag bit resets to the idle states when the fault has been cleared.  When the Alert Latch Enable bit is set to Latch mode, the Alert pin and Alert Flag bit remains active following a fault until the Mask/Enable Register has been read.
      - 1 = Latch enabled
      - 0 = Transparent (default) */
  alert-latch --set/int -> none:
    assert: 0 <= set <= 1
    oldMask/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    newMask/int := oldMask
    newMask     &= ~(ALERT-LATCH-ENABLE-BIT_)
    newMask     |= (set << ALERT-LATCH-ENABLE-OFFSET_)
    reg_.write-u16-be REGISTER-MASK-ENABLE_ newMask
    logger_.debug "alert-latch alert-pin $(set) is $(bits-16 oldMask) to $(bits-16 newMask)"

  /** alert-latch: Human readable alias for enabling alert latching */
  alert-latch --enable -> none:
    alert-latch --set=1

  /** alert-latch: Human readable alias for disabling alert latching */
  alert-latch --disable -> none:
    alert-latch --set=0

  /** alert-latch: Retrieve Latch Configuration */
  alert-latch -> bool:
    mask/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    latch/bool := false
    latchBit/int := ((mask & ALERT-LATCH-ENABLE-BIT_) >> ALERT-LATCH-ENABLE-OFFSET_) & ALERT-LATCH-ENABLE-LENGTH_
    if latchBit == 1: latch = true
    return latch
  
  /** alert-pin-polarity: Alert pin polarity functions
      - 1 = Inverted (active-high open collector)
      - 0 = Normal (active-low open collector) (default) */
  alert-pin-polarity --set/int -> none:
    assert: 0 <= set <= 1
    oldMask/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    newMask/int := oldMask
    newMask     &= ~(ALERT-PIN-POLARITY-BIT_)
    newMask     |= (set << ALERT-PIN-POLARITY-OFFSET_)
    reg_.write-u16-be REGISTER-MASK-ENABLE_ newMask
    logger_.debug "alert-pin-polarity: alert-pin $(set) is $(bits-16 oldMask) to $(bits-16 newMask)"

  /** alert-pin-polarity - Human readable alias for setting alert pin polarity */
  alert-pin-polarity --inverted -> none:  alert-pin-polarity --set=1
  alert-pin-polarity --normal   -> none:  alert-pin-polarity --set=0

  /** Retrieve configured alert pin polarity setting */
  alert-pin-polarity -> bool:
    // inverted = true, normal = false
    oldMask/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    polarityInverted/bool := false
    polarityInvertedBit/int := ((oldMask & ALERT-PIN-POLARITY-BIT_) >> ALERT-PIN-POLARITY-OFFSET_) & ALERT-PIN-POLARITY-LENGTH_
    if polarityInvertedBit == 1: polarityInverted = true
    logger_.debug "alert-pin-polarity: is $(polarityInvertedBit) [$(polarityInverted)]"
    return polarityInverted

  /** alert: return true if any of the three alerts exists
      Slightly different to other implementations. This method attempts to keep alerts visible as a value on the class object, so as not to be stored separately from the source of truth and therefore risk being stale.  So these functions attempt to source the current status of each alert from the device itself. */
  alert -> bool:
    register/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    if (register & ALERT-MATH-OVERFLOW-FLAG_) != 0: logger_.debug "alert: ALERT-MATH-OVERFLOW-FLAG_"
    if (register & ALERT-FUNCTION-FLAG_) != 0: logger_.debug "alert: ALERT-FUNCTION-FLAG_"
    if (register & ALERT-CONVERSION-READY-FLAG_) != 0: logger_.debug "alert: ALERT-CONVERSION-READY-FLAG_"
    checkMask    := ALERT-MATH-OVERFLOW-FLAG_ | ALERT-FUNCTION-FLAG_ | ALERT-CONVERSION-READY-FLAG_
    return (register & checkMask) != 0

  /** alert --clear: clear alerts */
  alert --clear -> none:
    // Not Tested well - manual suggests reading the MASK-ENABLE is enough to clear any alerts.
    register/int := reg_.read-u16-be REGISTER-MASK-ENABLE_

  /** alert --overflow: returns true if an overflow alert exists */
  alert --overflow  -> bool:
    register/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    overflow = false
    overflowBit := ((register & ALERT-MATH-OVERFLOW-FLAG_) >> ALERT-MATH-OVERFLOW-OFFSET_ ) & ALERT-MATH-OVERFLOW-LENGTH_
    if overflowBit == 1: overflow = true
    logger_.debug "alert --overflow: overflow bit is $(overflowBit) [$(overflow)]"
    return overflow

  limit-alert      -> bool:
    register/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    overflow := false
    overflowBit := ((register & ALERT-FUNCTION-FLAG_) >> ALERT-FUNCTION-OFFSET_ ) & ALERT-FUNCTION-LENGTH_
    if overflowBit == 1: overflow = true
    logger_.debug "limit-alert: configured limit bit is $(overflowBit) [$(overflow)]"
    return overflow

  /** Determine If Conversion is Complete
      Although the device can be read at any time, and the data from the last conversion is available, the Conversion Ready Flag bit is provided to help coordinate one-shot or triggered conversions. The Conversion Ready Flag bit is set after all conversions, averaging, and multiplications are complete. Conversion Ready Flag bit clears under the following conditions:
      1. Writing to the Configuration Register (except for Power-Down selection)
      2. Reading the Mask/Enable Register */
  conversion-ready-alert -> bool:
    register/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    conversionReady := false
    conversionReadyBit := ((register & ALERT-CONVERSION-READY-FLAG_) >> ALERT-CONVERSION-READY-OFFSET_ ) & ALERT-CONVERSION-READY-LENGTH_
    if conversionReadyBit == 1: conversionReady = true
    logger_.debug "conversion-ready-alert: conversion ready bit is $(conversionReadyBit) [$(conversionReady)]"
    return conversionReady

  /** conversion-ready: alias returning true/false for $conversion-ready-alert */
  conversion-ready -> bool:
    return conversion-ready-alert
  
  /** conversion-ready --set/int: Configure the alert function enabling the pin to be used to signal conversion ready. */
  conversion-ready --set/int -> none:
    assert: 0 <= set <= 1
    oldMask/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    newMask/int := oldMask
    newMask     &= ~(CONVERSION-READY-BIT_)
    newMask     |= (set << CONVERSION-READY-OFFSET_) // already bit shifted
    reg_.write-u16-be REGISTER-MASK-ENABLE_ newMask
    logger_.debug "conversion-ready: alert-pin $(set) is $(bits-16 oldMask) to $(bits-16 newMask)"

  /** conversion-ready --enable-alert-pin: Helpful alias for setting 'conversion-ready' on alert pin */
  conversion-ready --enable-alert-pin -> none:
    conversion-ready --set=1

  /** conversion-ready --disable-alert-pin: Helpful alias for setting 'conversion-ready' on alert pin */
  conversion-ready --disable-alert-pin -> none:
    conversion-ready --set=0

  /** conversion-time-us-from-enum: Returns microsecs for TIMING-x-US statics 0..7 */
  conversion-time-us-from-enum --code/int -> int:
    assert: 0 <= code <= 7
    if code == 0: return 140
    if code == 1: return 204
    if code == 2: return 332
    if code == 3: return 588
    if code == 4: return 1100
    if code == 5: return 2100
    if code == 6: return 4200
    if code == 7: return 8300
    return 1100  // default/defensive - should never happen

  /** sampling-rate-from-enum: Returns sample count for AVERAGE-x-SAMPLE statics 0..7 */
  sampling-rate-from-enum --code/int -> int:
    assert: 0 <= code <= 7
    if code == 0: return 1
    if code == 1: return 4
    if code == 2: return 16
    if code == 3: return 64
    if code == 4: return 128
    if code == 5: return 256
    if code == 6: return 512
    if code == 7: return 1024
    return 1  // default/defensive - should never happen

  /** estimated-conversion-time: estimate a maximum waiting time based on the configuration
      Done this way to prevent setting a global maxWait type value, to then have it fail based on times that are longer due to timing configurations  */
  estimated-conversion-time --ms -> int:
    // Read config and decode fields using masks/offsets
    register/int    := reg_.read-u16-be REGISTER-CONFIG_

    samplesCode/int    := (register & CONF-AVERAGE-MASK_)  >> CONF-AVERAGE-OFFSET_
    busCTcode/int      := (register & CONF-BUSVC-MASK_)    >> CONF-BUSVC-OFFSET_
    shuntCTcode/int    := (register & CONF-SHUNTVC-MASK_)  >> CONF-SHUNTVC-OFFSET_
    mode/int           := (register & CONF-MODE-MASK_)     >> CONF-MODE-OFFSET_

    samplingRate/int   := sampling-rate-from-enum            --code = samplesCode
    busCT/int          := conversion-time-us-from-enum       --code = busCTcode
    shuntCT/int        := conversion-time-us-from-enum       --code = shuntCTcode

    // Mode 0x7 = bus+shunt continuous, 0x3 = bus+shunt triggered (single-shot).
    // If converting to support bus-only or shunt-only modes, drop the other term.
    totalus/int    := (busCT + shuntCT) * samplingRate

    // Add a small guard factor (~10%) to be conservative
    totalus = ((totalus * 11.0) / 10.0).to-int

    // Return milliseconds, minimum 1 ms
    totalms := ((totalus + 999) / 1000).to-int  // ceil
    if totalms < 1: totalms = 1

    //logger_.debug "estimated-conversion-time: --ms is: $(totalms)ms"
    return totalms

  // INFORMATION FUNCTIONS

  /** Get Manufacturer/Die identifiers
      Maybe useful if expanding driver to suit an additional sibling device */
  manufacturer-id -> int:
    manid := reg_.read-u16-be REGISTER-MANUF-ID_
    //logger_.debug "manufacturer-id: is 0x$(%04x manid) [$(manid)]"
    return manid
  
  /** device-identification: returns integer of device ID bits
      REGISTER-DIE-ID_ register, bits 4-15 Stores the device identification bits */
  device-identification -> int:
    register := reg_.read-u16-be REGISTER-DIE-ID_
    dieidDid := (register & DIE-ID-DID-MASK_) >> 4
    //logger_.debug "device-identification: is 0x$(%04x dieidDid) [$(dieidDid)]"
    return dieidDid

  /** device-revision: Die Revision ID Bits
      REGISTER-DIE-ID_ register, bits 0-3 store the device revision number bits */
  device-revision -> int:
    register := reg_.read-u16-be REGISTER-DIE-ID_
    dieidRid := (register & DIE-ID-RID-MASK_)
    //logger_.debug "device-revision: is 0x$(%04x dieidRid) [$(dieidRid)]"
    return dieidRid

  // TROUBLESHOOTING FUNCTIONS

  /** infer-shunt-resistor: Infer Shunt Resistor using a known load resistor
      Averages a few samples for stability, ensures both voltages come from the same conversion, and returns the estimated shunt value.
      On Accuracy:
      - Known load tolerance dominates: use a 0.1–1% resistor if possible
      - Make sure VBUS & load node (IN−) are tied
      - Kelvin the shunt if possible: sense pins at the shunt pads
      - Perform test/readings after the load settles - average some samples
      - Low-current corner: if Vshunt is just a few tens of µV, quantization/noise can move the estimate; use a load that draws a few mA+ to get a clean mV-level Vsh. */
  infer-shunt-resistor --loadResistor/float -> float:
    assert: loadResistor > 0.0

    // Make sure we read one coherent conversion
    single-measurement
    wait-until-conversion-completed

    // Light Averaging
    loadVoltageSum/float       := 0.0
    shuntVoltageSum/float      := 0.0
    samples                    := 8
    samples.repeat:
      loadVoltageSum           += bus-voltage --volts
      shuntVoltageSum          += shunt-voltage --volts

    // Replace values with calculated average
    loadVoltage/float          := loadVoltageSum / samples.to-float
    shuntVoltage/float         := shuntVoltageSum   / samples.to-float

    // Estimate current via Ohm's law on the known load
    currentEstimate/float := loadVoltage / loadResistor
    assert: currentEstimate > 0.0

    shuntResistorEstimate/float := shuntVoltage / currentEstimate
    logger_.debug "infer-shunt-resistor: Vload=$(loadVoltage) V  Vsh=$(shuntVoltage) V  Rload=$(loadResistor) Ohm  -> I=$(currentEstimate)A  Rsh_est=$(shuntResistorEstimate) Ohm"
    return shuntResistorEstimate

  /** infer-shunt-resistor --loadCurrent: Determine shunt resistor value from known load
      Useful if you have a DMM clamp or source.  See notes above for similar function. */
  infer-shunt-resistor --loadCurrent/float -> float:
    assert: loadCurrent > 0.0

    // Make sure we read one coherent conversion
    single-measurement
    wait-until-conversion-completed
    
    // take some samples and average the shuntVoltage a bit
    shuntVoltageSum/float       := 0.0
    samples                     := 8
    samples.repeat:
      shuntVoltageSum += shunt-voltage --volts
      
    shuntVoltage/float          := shuntVoltageSum / samples.to-float
    shuntResistorEstimate/float := shuntVoltage / loadCurrent
    logger_.debug "infer-shunt-resistor: Vsh=$(shuntVoltage)V  I_known=$(loadCurrent)A  -> Rsh_est=$(shuntResistorEstimate)Ω"
    return shuntResistorEstimate


  /** verify-tied-bus-load: Determine VBUS and VLOAD are different
      Evaluates if the bus and load voltages are different (eg not tied). Useful for diagnostic functions only.  If the voltages are the same, it is not proof that they are tied, this attempts to check for the simple case where values indiate it is not tied. */
  verify-tied-bus-load -> bool:
    // Optional: ensure fresh data
    single-measurement
    wait-until-conversion-completed

    busVoltage/float := bus-voltage --volts
    loadVoltage/float := load-voltage --volts
    busLoadDelta/float := (busVoltage - loadVoltage).abs
  
    logger_.debug "verify-tied-bus-load: Bus = $(%0.8f busVoltage)V, Load = $(%0.8f loadVoltage)V, Delta = $(%0.8f busLoadDelta)V"
    if busLoadDelta < 0.01:       // <10 mV difference
      logger_.debug "verify-tied-bus-load: Bus and load values appear the same (tied?)     Delta=$(%0.8f busLoadDelta)V"
      return true
    else if busLoadDelta < 0.05:  // 10–50 mV: maybe wiring drop
      logger_.debug "verify-tied-bus-load: Bus/load differ slightly (check traces/wiring)  Delta=$(%0.8f busLoadDelta)V"
      return false
    else:
      logger_.debug "verify-tied-bus-load: Bus and load differ significantly (not tied)    Delta=$(%0.8f busLoadDelta)V"
      return false

  /** Print Diagnostic Information
      Prints relevant measurement information to allow someone with a Voltmeter to double check what is measured and compare it.  Also calculates/compares using Ohms Law (V=I*R) */
  print-diagnostics -> none:
    // Optional: ensure fresh data
    single-measurement
    wait-until-conversion-completed

    shuntVoltage/float               := shunt-voltage --volts
    loadVoltage/float                := bus-voltage --volts              // what the load actually sees (VBUS, eg IN−)
    supplyVoltage/float              := loadVoltage + shuntVoltage       // upstream rail (IN+ = IN− + Vsh)
    shuntVoltageDelta/float          := supplyVoltage - loadVoltage      // same as vsh
    shuntVoltageDeltaPct/float       := 0.0
    if supplyVoltage > 0.0: shuntVoltageDeltaPct = (shuntVoltageDelta / supplyVoltage) * 100.0

    calibrationValue/int             := calibration-value
    currentRaw/int                   := reg_.read-i16-be REGISTER-SHUNT-CURRENT_
    leastSignificantBit/float        := 0.00512 / (calibrationValue.to-float * shunt-resistor_)
    currentChip/float                := currentRaw * leastSignificantBit
    currentVR/float                  := shuntVoltage / shunt-resistor_

    // CROSSCHECK: between chip/measured current and V/R reconstructed current
    currentDifference/float          := (currentChip - currentVR).abs
    currentDifferencePct/float       := 0.0
    if (currentVR != 0.0): 
      currentDifferencePct           = (currentDifference / currentVR) * 100.0

    // CROSSCHECK: shunt voltage (measured vs reconstructed)
    shuntVoltageCalculated/float     := currentChip * shunt-resistor_
    shuntVoltageDifference/float     := (shuntVoltage - shuntVoltageCalculated).abs
    shuntVoltageDifferencePct/float  := 0.0
    if (shuntVoltage != 0.0): 
      shuntVoltageDifferencePct      = (shuntVoltageDifference / shuntVoltage).abs * 100.0

    print "DIAG :"
    print "    ----------------------------------------------------------"
    print "    Shunt Resistor    =  $(%0.8f shunt-resistor_) Ohm (Configured in code)"
    print "    Vload    (IN-)    =  $(%0.8f loadVoltage)  V"
    print "    Vsupply  (IN+)    =  $(%0.8f supplyVoltage)  V"
    print "    Shunt V delta     =  $(%0.8f shuntVoltageDelta)  V"
    print "                      = ($(%0.8f shuntVoltageDelta*1000.0)  mV)"
    print "                      = ($(%0.3f shuntVoltageDeltaPct)% of supply)"
    print "    Vshunt (direct)   =  $(%0.8f shuntVoltage)  V"
    print "    ----------------------------------------------------------"
    print "    Calibration Value =  $(calibrationValue)"
    print "    I (raw register)  = ($(currentRaw))"
    print "                 LSB  = ($(%0.8f leastSignificantBit)  A/LSB)"
    print "    I (from module)   =  $(%0.8f currentChip)  A"
    print "    I (from V/R)      =  $(%0.8f currentVR)  A"
    print "    ----------------------------------------------------------"
    if currentDifferencePct < 5.0:
      print "    Check Current       : OK - Currents agree ($(%0.3f currentDifferencePct)% under/within 5%)"
    else if currentDifferencePct < 20.0:
      print "    Check Current       : WARNING (5% < $(%0.3f currentDifferencePct)% < 20%) - differ noticeably"
    else:
      print "    Check Current       : BAD!! ($(%0.3f currentDifferencePct)% > 20%): check calibration or shunt value"
    if shuntVoltageDifferencePct < 5.0:
      print "    Check Shunt Voltage : OK - Shunt voltages agree ($(%0.3f shuntVoltageDifferencePct)% under/within 5%)"
    else if shuntVoltageDifferencePct < 20.0:
      print "    Check Shunt Voltage : WARNING (5% < $(%0.3f shuntVoltageDifferencePct)% < 20%) - differ noticeably"
    else:
      print "    Check Shunt Voltage : BAD!! ($(%0.3f shuntVoltageDifferencePct)% > 20%): shunt voltage mismatch"

  /** Displays bitmasks nicely */
  bits-16 x/int --display-bits/int=8 -> string:
    if (x > 255) or (display-bits > 8):
      outStr := "$(%b x)"
      outStr = outStr.pad --left 16 '0'
      outStr = "$(outStr[0..4]).$(outStr[4..8]).$(outStr[8..12]).$(outStr[12..16])"
      return outStr
    else:
      outStr := "$(%b x)"
      outStr = outStr.pad --left 8 '0'
      outStr = "$(outStr[0..4]).$(outStr[4..8])"
      return outStr
