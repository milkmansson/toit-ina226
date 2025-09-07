// Copyright (C) 2025 Ian
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.
// Toit Driver Library for an INA226 module, DC Shunt current and power sensor
// Module not unlike this: https://esphome.io/components/sensor/ina226/
//
// Credits: Code has been shamelessly plagiarised/ported from work originally
//          by Wolfgang Ewald <WEwald@gmx.de> originally published on Github
//          here https://github.com/wollewald/INA226_WE  
//
// TI Module Datasheet:
// https://www.ti.com/lit/ds/symlink/ina226.pdf
//
// Qdos: Other code reviewed whilst working this out:
// https://github.com/RobTillaart/INA226/blob/master/INA226.cpp
//


/** 

$DEFAULT-I2C-ADDRESS ($ hotlinks to code location!)  Used for parameters

*/

import binary
import serial.device as serial
import serial.registers as registers

//DEFAULT-CALIBRATION-VALUE             ::= 0x0800
//DEFAULT-CALIBRATION-VALUE             ::= 0x0831 // calculated during testing 2025-09-05
DEFAULT-I2C-ADDRESS                   ::= 0x0040 // 64 appears to be the default
                                            // with jumpers valid values to 79
                                            // See table 6-2

// Alert Types that can set off the pin
INA226-ALERT-SHUNT-OVER-VOLTAGE       ::= 0x8000
INA226-ALERT-SHUNT-UNDER-VOLTAGE      ::= 0x4000
INA226-ALERT-BUS-OVER-VOLTAGE         ::= 0x2000
INA226-ALERT-BUS-UNDER-VOLTAGE        ::= 0x1000
INA226-ALERT-POWER-OVER               ::= 0x0800
INA226-ALERT-CURRENT-OVER             ::= 0xFFFE
INA226-ALERT-CURRENT-UNDER            ::= 0xFFFF
INA226-ALERT-CONVERSION-READY         ::= 0x0400

//  returned by getAlertFlag
INA226-ALERT-CONVERSION-READY-FLAG    ::= 0x0008
INA226-ALERT-CONVERSION-READY-OFFSET  ::= 0x03
INA226-ALERT-CONVERSION-READY-LENGTH  ::= 0x01
INA226-ALERT-FUNCTION-FLAG            ::= 0x0010
INA226-ALERT-FUNCTION-OFFSET          ::= 0x04
INA226-ALERT-FUNCTION-LENGTH          ::= 0x01
INA226-ALERT-MATH-OVERFLOW-FLAG       ::= 0x0004
INA226-ALERT-MATH-OVERFLOW-OFFSET     ::= 0x02
INA226-ALERT-MATH-OVERFLOW-LENGTH     ::= 0x01
INA226-ALERT-PIN-POLARITY-BIT         ::= 0x0002
INA226-ALERT-PIN-POLARITY-OFFSET      ::= 0x01
INA226-ALERT-PIN-POLARITY-LENGTH      ::= 0x01
INA226-ALERT-LATCH-ENABLE-BIT         ::= 0x0001
INA226-ALERT-LATCH-ENABLE-OFFSET      ::= 0x00
INA226-ALERT-LATCH-ENABLE-LENGTH      ::= 0x01
INA226-CONVERSION-READY-BIT           ::= 0x0800
INA226-CONVERSION-READY-OFFSET        ::= 0x0A
INA226-CONVERSION-READY-LENGTH        ::= 0x01

//  returned by setMaxCurrentShunt
INA226-ERR-NONE                       ::= 0x0000
INA226-ERR-SHUNTVOLTAGE-HIGH          ::= 0x8000
INA226-ERR-MAXCURRENT-LOW             ::= 0x8001
INA226-ERR-SHUNT-LOW                  ::= 0x8002
INA226-ERR-NORMALIZE-FAILED           ::= 0x8003

INA226-MINIMAL-SHUNT-OHM              ::= 0.001
INA226-MAX-WAIT-MS                    ::= 600   //  millis
INA226-MAX-SHUNT-VOLTAGE              ::= (81.92 / 1000)

//  CONFIGURATION BITMASKS
INA226-CONF-RESET-MASK                ::= 0x8000
INA226-CONF-AVERAGE-MASK              ::= 0x0E00
INA226-CONF-AVERAGE-OFFSET            ::= 0x09
INA226-CONF-BUSVC-MASK                ::= 0x01C0
INA226-CONF-BUSVC-OFFSET              ::= 0x06
INA226-CONF-SHUNTVC-MASK              ::= 0x0038
INA226-CONF-SHUNTVC-OFFSET            ::= 0x03
INA226-CONF-MODE-MASK                 ::= 0x0007
INA226-CONF-MODE-OFFSET               ::= 0x00

// AVERAGE SAMPLE SIZE ENUM 
INA226-AVERAGE-1-SAMPLE               ::= 0x0000
INA226-AVERAGE-4-SAMPLES              ::= 0x0001
INA226-AVERAGE-16-SAMPLES             ::= 0x0002
INA226-AVERAGE-64-SAMPLES             ::= 0x0003
INA226-AVERAGE-128-SAMPLES            ::= 0x0004
INA226-AVERAGE-256-SAMPLES            ::= 0x0005
INA226-AVERAGE-512-SAMPLES            ::= 0x0006
INA226-AVERAGE-1024-SAMPLES           ::= 0x0007

// BVCT and SVCT conversion timing ENUM
INA226-TIMING-140-us                  ::= 0x0000
INA226-TIMING-204-us                  ::= 0x0001
INA226-TIMING-332-us                  ::= 0x0002
INA226-TIMING-588-us                  ::= 0x0003
INA226-TIMING-1100-us                 ::= 0x0004
INA226-TIMING-2100-us                 ::= 0x0005
INA226-TIMING-4200-us                 ::= 0x0006
INA226-TIMING-8300-us                 ::= 0x0007

// 'Measure Mode' (includes OFF)
INA226-MODE-POWER-DOWN                ::= 0x0000
INA226-MODE-TRIGGERED                 ::= 0x0003
INA226-MODE-CONTINUOUS                ::= 0x0007

// Die & Manufacturer Info Masks
INA226-DIE-ID-RID-MASK                ::= 0x000F
INA226-DIE-ID-DID-MASK                ::= 0xFFF0

class Driver:
  /*****************************************************************
  * Written by Wolfgang (Wolle) Ewald
  * https://wolles-elektronikkiste.de/en/ina226-current-and-power-sensor (English)
  * https://wolles-elektronikkiste.de/ina226 (German)
  ******************************************************************/

  static INA226-REGISTER-CONFIG_         ::= 0x00  //RW  // All-register reset, shunt voltage and bus voltage ADC conversion times and averaging, operating mode.
  static INA226-REGISTER-SHUNT-VOLTAGE_  ::= 0x01  //R   // Shunt voltage measurement data
  static INA226-REGISTER-BUS-VOLTAGE_    ::= 0x02  //R   // Bus voltage measurement data
  static INA226-REGISTER-LOAD-POWER_     ::= 0x03  //R   // value of the calculated power being delivered to the load
  static INA226-REGISTER-SHUNT-CURRENT_  ::= 0x04  //R   // value of the calculated current flowing through the shunt resistor
  static INA226-REGISTER-CALIBRATION_    ::= 0x05  //RW  // Sets full-scale range and LSB of current and power measurements. Overall system calibration.
  static INA226-REGISTER-MASK-ENABLE_    ::= 0x06  //RW  // Alert configuration and Conversion Ready flag
  static INA226-REGISTER-ALERT-LIMIT_    ::= 0x07  //RW  // limit value to compare to the selected Alert function
  static INA226-REGISTER-MANUF-ID_       ::= 0xFE  //R   // Contains unique manufacturer identification number.
  static INA226-REGISTER-DIE-ID_         ::= 0xFF  //R   // Contains unique die identification number

  // Globals
  debug_/bool                := false
  reg_/registers.Registers   := ?
  
  currentDivider_mA_/float   := 0.0
  pwrMultiplier_mW_/float    := 0.0
  lastMeasureMode_/int       := INA226-MODE-CONTINUOUS
  current-LSB_/float         := 0.0
  shuntResistor_/float       := 0.0
  corrFactorA_/float         := 0.0

  debug-mode --enable -> none:
    debug_ = true

  debug-mode --disable -> none:
    debug_ = false

  // Class Constructor
  constructor dev/serial.Device:
    reg_ = dev.registers
    initialise-device_

  constructor dev/serial.Device --debug:
    reg_ = dev.registers
    debug-mode --enable
    initialise-device_
  
  // CONFIGURATION FUNCTIONS

  // Initial Device Configuration
  //
  initialise-device_ -> none:
    // reset/initialise module
    reset_

    // NOTE:  Found an error by factor 100 and couldn't figure this out in any way
    //        left this hack (feature) in to allow a correction factor for values 
    //        match up with voltmeter. Before using the library, verify this value
    //        matches measurements IRL. 
    corrFactorA_ = 100.0

    // NOTE:  The Current Register (04h) and Power Register (03h) default to '0' 
    //        because the Calibration register defaults to '0', yielding zero current
    //        and power values until the Calibration register is programmed.
    //        write initial calibration value, initial average value and conversion 
    //        time.  This is not done here to ensure resistor-range does this.
    // calibration-value --value=DEFAULT-CALIBRATION-VALUE

    // Initialise Default sampling, conversion timing, and measuring mode
    sampling-rate       --rate=INA226-AVERAGE-512-SAMPLES
    conversion-time     --time=INA226-TIMING-1100-us
    measure-mode        --mode=INA226-MODE-CONTINUOUS

    // Set Defaults for Resistor Range
    // NOTE:  There appears to have been originally two constants/values for 'current range'
    //        MA_400 and MA_800 - I tested these and found that my voltmeter agreed when
    //        current range is set to 0.800a - eg 800ma.
    // NOTE:  Whilst not documented well for newbies like me, I assumed the resistor value
    //        needs to match the one on the board.  Mine is R100, which I assumed 0.1 Ohm.
    resistor-range      --resistor=0.100 --current-range=0.8
    
    // NOTE:  Performing a single measurement here assists with accuracy for initial
    //        measurements.
    single-measurement
    wait-until-conversion-completed
    
    // NOTE:  Using this helper function, the actual values used in the calculations are visible
    if debug_: print-diagnostics

    // Testing of functions
    /*if debug_:
      print "Test load-current --amps      :$(load-current --amps)"
      print "Test load-current --milliamps :$(load-current --milliamps)"
      val1 := ?
      val1 = manufacturer-id
      val1 = die-id
      val1 = die-id --rid
      val1 = die-id --did
      busy
      print "*      : single-measurement --nowait "
      measure-mode   --mode=INA226-MODE-TRIGGERED
      sampling-rate  --rate=INA226-AVERAGE-256-SAMPLES
      print "*      : single-measurement"
      single-measurement
      print "*      :                             ... done"
      
      conversion-ready --enable-alert-pin
      alert-latch --enable
      alert-pin-polarity --inverted
      val1 = conversion-ready

      set-alert --type=INA226-ALERT-BUS-OVER-VOLTAGE --limit=3.5
      val1 = alert-limit
      conversion-ready --enable-alert-pin
      alert-latch --disable
      val1 = alert-latch
      alert-pin-polarity --normal
      val1 = alert-pin-polarity
      sampling-rate  --rate=INA226-AVERAGE-256-SAMPLES
      measure-mode   --mode=INA226-MODE-CONTINUOUS
  */

  // Reset Device
  // NOTE:  Setting bit 16 resets the device, afterwards the bit self-clears
  // 
  reset_ -> none:
    oldMask := reg_.read-u16-be INA226-REGISTER-CONFIG_
    newMask := oldMask | INA226-CONF-RESET-MASK
    reg_.write-u16-be INA226-REGISTER-CONFIG_ newMask
    sleep --ms=(estimated-conversion-time --ms)
    nowMask := reg_.read-u16-be INA226-REGISTER-CONFIG_
    if debug_: print "*      : reset - 0x$(%02x oldMask) [to 0x$(%02x newMask)] - after reset 0x$(%02x nowMask)"

  // Set Calibration Value 
  // NOTE:  Sets Calibration Value Outright
  // 
  calibration-value --value/int -> none:
    // Replaces the existing calibration value 
    oldRegister := reg_.read-u16-be INA226-REGISTER-CALIBRATION_
    reg_.write-u16-be INA226-REGISTER-CALIBRATION_ value
    if debug_: print "*      : calibration-value         changed from $(oldRegister) to $(value)"
    calCheck/int := calibration-value
    if debug_: print "*      : calibration-value CHECKED changed from $(oldRegister) to $(calCheck)"
    assert: ((calCheck >= 1500) and (calCheck <= 3000))  // sanity check

  // Get Calibration Value
  //
  calibration-value -> int:
    register := reg_.read-u16-be INA226-REGISTER-CALIBRATION_
    if debug_: print "*      : calibration-value retrieved $(register)"
    return register

  // Adjust Calibration Value by Factor
  // NOTE:  Retrieves and adjusted calibration value by a factor
  //
  calibration-value --factor/int -> none:
    oldCalibrationValue := calibration-value
    newCalibrationValue := oldCalibrationValue * factor
    calibration-value --value=newCalibrationValue
    if debug_: print "*      : calibration-value factor $(factor) adjusts from $(oldCalibrationValue) to $(newCalibrationValue)"

  // Adjust Sampling Rate for measurements
  //
  sampling-rate --rate/int -> none:
    oldMask/int  := reg_.read-u16-be INA226-REGISTER-CONFIG_
    newMask/int  := oldMask
    newMask      &= ~(INA226-CONF-AVERAGE-MASK)
    newMask      |= (rate << 9)
    reg_.write-u16-be INA226-REGISTER-CONFIG_ newMask
    if debug_: print "*      : sampling-rate set from 0x$(%02x oldMask) to 0x$(%02x newMask)"

  // Retrieve current sampling rate code/enum value
  // 
  sampling-rate --code -> int:
    mask := reg_.read-u16-be INA226-REGISTER-CONFIG_
    return ((mask & INA226-CONF-AVERAGE-MASK) >> 9)

  // Return human readable sampling count number
  // 
  sampling-rate --count -> int:
    return sampling-rate-from-enum --code=(sampling-rate --code)

  // Set Conversion Time
  // NOTE:  The conversion time setting tells the ADC how long to spend on a single 
  //        measurement of either the shunt voltage or the bus voltage.
  //        - Longer time = more samples averaged inside = less noise, higher resolution.
  //        - Shorter time = fewer samples = faster updates, but noisier.
  // NOTE:  Both Bus and Shunt have separate conversion times
  //        - Bus voltage = the “supply” or “load node” you’re monitoring.
  //        - Shunt voltage = the tiny drop across your shunt resistor.
  //        - Current isn’t measured directly — it’s computed later from Vshunt/Rshunt
  //
  conversion-time --bus/int -> none:
    oldMask/int := reg_.read-u16-be INA226-REGISTER-CONFIG_
    newMask/int := oldMask
    newMask     &= ~INA226-CONF-BUSVC-MASK
    newMask     |= (bus << INA226-CONF-BUSVC-OFFSET)
    reg_.write-u16-be INA226-REGISTER-CONFIG_ newMask
    if debug_: print "*      : conversion-time --bus set from 0x$(%02x oldMask) to 0x$(%02x newMask)"
  
  conversion-time --shunt/int -> none:
    oldMask/int := reg_.read-u16-be INA226-REGISTER-CONFIG_
    newMask/int := oldMask
    newMask     &= ~INA226-CONF-SHUNTVC-MASK
    newMask     |= (shunt << INA226-CONF-SHUNTVC-OFFSET)
    reg_.write-u16-be INA226-REGISTER-CONFIG_ newMask
    if debug_: print "*      : conversion-time --shunt set from 0x$(%02x oldMask) to 0x$(%02x newMask)"

  // Sets both to the same when one value is given
  conversion-time --time/int -> none:
    conversion-time --shunt=time
    conversion-time --bus=time

  // Sets Measure Mode
  // NOTE:  Keeps track of last measure mode set, in a global. Ensures device comes back on
  //        into the same mode using 'PowerOn'
  measure-mode --mode/int -> none:
    oldMask/int := reg_.read-u16-be INA226-REGISTER-CONFIG_
    newMask/int := oldMask
    newMask     &= ~(INA226-CONF-MODE-MASK)
    newMask     |= mode  //low value, no left shift offset
    reg_.write-u16-be INA226-REGISTER-CONFIG_ newMask
    if debug_: print "*      : measure-mode set from 0x$(%02x oldMask) to 0x$(%02x newMask)"
    if (mode != INA226-MODE-POWER-DOWN): lastMeasureMode_ = mode

  // Set resistor and current range, independently 
  // NOTE:  Resistor value in ohm, Current range in A
  // 
  resistor-range --resistor/float --current-range/float -> none:
    shuntResistor_       = resistor    // Cache to global for later use
    current-LSB_         = current_range / 32768.0                // A per bit (LSB)
    if debug_: print "*      : resistor-range: current per bit = $(current-LSB_)A"
    calibrationValue   := 0.00512 / (current-LSB_ * resistor)
    if debug_: print "*      : resistor-range: calibration value becomes = $(calibrationValue)"
    calibration-value --value=(calibrationValue).to-int
    currentDivider_mA_  = 0.001 / current-LSB_
    pwrMultiplier_mW_   = 1000.0 * 25.0 * current-LSB_
    // TODO: Check for accuracy on the to-int
  
  // MEASUREMENT FUNCTIONS

  shunt-current --amps -> float:
    register   := reg_.read-i16-be INA226-REGISTER-SHUNT-CURRENT_
    return (register * current-LSB_ * corrFactorA_)
  
  shunt-current --milliamps -> float:   return ((shunt-current --amps) * 1000.0)

  shunt-voltage --volts -> float:
    register := reg_.read-i16-be INA226-REGISTER-SHUNT-VOLTAGE_
    return (register * 0.0000025)

  shunt-voltage --millivolts -> float:  return (shunt-voltage --volts) * 1000.0
  
  // Upstream voltage, before the shunt (IN+).
  // NOTE:  That is the rail straight from the power source, minus any drop across
  //        the shunt. Since INA226 doesn’t have a dedicated pin for this, it can
  //        be reconstructed by: Vsupply = Vbus + Vshunt.   i.e. add the measured 
  //        bus voltage (load side) and the measured shunt voltage.
  supply-voltage --volts -> float:
    return ((bus-voltage --volts) + (shunt-voltage --volts))

  supply-voltage --millivolts -> float:
    return (supply-voltage --volts) * 1000.0

  bus-voltage --volts -> float:
    // whatever is wired to the VBUS pin.  On most breakout boards, VBUS is tied 
    // internally to IN− (the low side of the shunt). So in practice, “bus voltage” 
    // usually means the voltage at the load side of the shunt.  This is what the 
    // load actually sees as its supply rail.
    register := reg_.read-i16-be INA226-REGISTER-BUS-VOLTAGE_
    return (register * 0.00125)

  bus-voltage  --millivolts -> float:
    return (bus-voltage --volts) * 1000.0
  
  load-power --milliwatts -> float:
    // Using the cached multiplier [pwrMultiplier_mW_ = 1000 * 25 * current-LSB_]
    register := reg_.read-u16-be INA226-REGISTER-LOAD-POWER_
    return (register * pwrMultiplier_mW_).to-float

  load-power --watts -> float:
    return (load-power --milliwatts) / 1000.0

  // Aliases to help with user understanding of terms
  load-voltage --volts -> float:       return (bus-voltage --volts)
  load-voltage --millivolts -> float:  return (bus-voltage --volts) * 1000.0
  load-current --amps -> float:        return (shunt-current --amps)
  load-current --milliamps -> float:   return (shunt-current --milliamps)

  // Simple aliases for enabling and disabling device 
  // NOTE:  The powering on relies on the cached global variable which
  //        records what it was last set to.
  power-down -> none:
    measure-mode --mode=INA226-MODE-POWER-DOWN
  power-up -> none:
    measure-mode --mode=lastMeasureMode_
    sleep --ms=(estimated-conversion-time --ms)

  // Returns true if conversion is still ongoing
  busy -> bool:
    register/int := reg_.read-u16-be INA226-REGISTER-MASK-ENABLE_            // clears CNVR (Conversion Ready) Flag
    val/bool     :=  ((register & INA226-ALERT-CONVERSION-READY-FLAG) == 0)
    // if debug_: print "*      : busy compares  reg:val                              $(bits-16 register) to $(bits-16 INA226-ALERT-CONVERSION-READY-FLAG)"
    // if debug_: print "*      : busy returns $(val)"
    return val

  wait-until-conversion-completed -> none:
    maxWaitTimeMs/int   := INA226-MAX-WAIT-MS
    curWaitTimeMs/int   := 0
    sleepIntervalMs/int := 50
    while busy:                                                               // checks if sampling is completed
        // if debug_: print "*      : waitUntilConversionCompleted waiting $(curWaitTimeMs)ms of max $(maxWaitTimeMs)ms"
        sleep --ms=sleepIntervalMs
        curWaitTimeMs += sleepIntervalMs
        if curWaitTimeMs >= maxWaitTimeMs:
          if debug_: print "*      : waitUntilConversionCompleted maxWaitTime $(maxWaitTimeMs)ms exceeded - breaking"
          break
    if debug_: print "*      : waitUntilConversionCompleted waited $(curWaitTimeMs)ms of max $(maxWaitTimeMs)ms"

  // Single Measurement - wait for completion
  //
  single-measurement -> none:
    single-measurement --nowait
    wait-until-conversion-completed
  
  // Perform a single conversion - without waiting
  //
  single-measurement --nowait -> none:
    maskRegister/int   := reg_.read-u16-be INA226-REGISTER-MASK-ENABLE_      // clears CNVR (Conversion Ready) Flag
    confRegister/int   := reg_.read-u16-be INA226-REGISTER-CONFIG_     
    reg_.write-u16-be INA226-REGISTER-CONFIG_ confRegister                   // Starts conversion

  // ALERT FUNCTIONS 

  // Configuring the various alert types
  // NOTE:  Requires a value from the alert type enum.  If multiple functions are enabled
  //        the highest significant bit position Alert Function (D15-D11) takes priority 
  //        and responds to the Alert Limit Register.  ie. only one alert of one type
  //        can be configured simultaneously.  Whatever is in the alert value (register) 
  //        at that time, is then the alert trigger value.
  //
  set-alert --type/int --limit/float -> none:
    alertLimit/float := 0.0

    if type == INA226-ALERT-SHUNT-OVER-VOLTAGE:
      alertLimit = limit * 400          
    else if type == INA226-ALERT-SHUNT-UNDER-VOLTAGE:
      alertLimit = limit * 400
    else if type == INA226-ALERT-CURRENT-OVER:
      type = INA226-ALERT-SHUNT-OVER-VOLTAGE
      alertLimit = limit * 2048 * currentDivider_mA_ / (calibration-value).to-float
    else if type == INA226-ALERT-CURRENT-UNDER:
      type = INA226-ALERT-SHUNT-UNDER-VOLTAGE
      alertLimit = limit * 2048 * currentDivider_mA_ / (calibration-value).to-float
    else if type == INA226-ALERT-BUS-OVER-VOLTAGE:
      alertLimit = limit * 800
    else if type == INA226-ALERT-BUS-UNDER-VOLTAGE:
      alertLimit = limit * 800
    else if type == INA226-ALERT-POWER-OVER:
      alertLimit = limit / pwrMultiplier_mW_
    else:
      if debug_: print "*      : set-alert unexpected alert type"
      throw "set-alert unexpected alert type"
    
    // Set Alert Type Flag
    oldMask/int := reg_.read-u16-be INA226-REGISTER-MASK-ENABLE_
    newMask/int := oldMask
    newMask     &= ~(0xF800)    // clear old alert values (bits D11 to D15) - only one alert allowed at once
    newMask     |= type         // already bit shifted in the mask constants!
    reg_.write-u16-be INA226-REGISTER-MASK-ENABLE_ newMask
    // if debug_: print "*      : set-alert mask set from 0x$(%02x oldMask) to 0x$(%02x newMask)"
    if debug_: print "*      : set-alert mask                                      $(bits-16 oldMask) to $(bits-16 newMask)"

    // Set Alert Limit Value
    reg_.write-u16-be INA226-REGISTER-ALERT-LIMIT_ (alertLimit).to-int
    if debug_: print "*      : set-alert alert limit set to $(alertLimit)"

  // Alert "Latching"
  // NOTE:  When the Alert Latch Enable bit is set to Transparent mode, the Alert 
  //        pin and Flag bit resets to the idle states when the fault has been cleared.
  //        When the Alert Latch Enable bit is set to Latch mode, the Alert pin and
  //        Alert Flag bit remains active following a fault until the Mask/Enable 
  //        Register has been read.
  //        1 = Latch enabled
  //        0 = Transparent (default)
  //
  alert-latch --set/int -> none:
    assert: 0 <= set <= 1
    oldMask/int := reg_.read-u16-be INA226-REGISTER-MASK-ENABLE_
    newMask/int := oldMask
    newMask     &= ~(INA226-ALERT-LATCH-ENABLE-BIT)
    newMask     |= (set << INA226-ALERT-LATCH-ENABLE-OFFSET)
    reg_.write-u16-be INA226-REGISTER-MASK-ENABLE_ newMask
    // if debug_: print "*      : alert-latch enable set from 0x$(%01x oldMask) to 0x$(%01x newMask)"
    if debug_: print "*      : alert-latch alert-pin $(set) is                          $(bits-16 oldMask) to $(bits-16 newMask)"

  // Human readable alias for setting alert latching
  //
  alert-latch --enable -> none:
    alert-latch --set=1

  // Human readable alias for setting alert latching
  //
  alert-latch --disable -> none:
    alert-latch --set=0

  // Retrieve Latch Configuration
  //
  alert-latch -> bool:
    mask/int := reg_.read-u16-be INA226-REGISTER-MASK-ENABLE_
    latch/bool := false
    latchBit/int := ((mask & INA226-ALERT-LATCH-ENABLE-BIT) >> INA226-ALERT-LATCH-ENABLE-OFFSET) & INA226-ALERT-LATCH-ENABLE-LENGTH
    if latchBit == 1: latch = true
    if debug_: print "*      : alert-latch is is $(latchBit) [$(latch)]"
    return latch
  
  // Alert pin polarity functions
  // NOTE:  
  //        1 = Inverted (active-high open collector)
  //        0 = Normal (active-low open collector) (default)
  //
  alert-pin-polarity --set/int -> none:
    assert: 0 <= set <= 1
    oldMask/int := reg_.read-u16-be INA226-REGISTER-MASK-ENABLE_
    newMask/int := oldMask
    newMask     &= ~(INA226-ALERT-PIN-POLARITY-BIT)
    newMask     |= (set << INA226-ALERT-PIN-POLARITY-OFFSET)
    reg_.write-u16-be INA226-REGISTER-MASK-ENABLE_ newMask
    //if debug_: print "*      : alert-pin-polarity enable set from 0x$(%01x oldMask) to 0x$(%01x newMask)"
    if debug_: print "*      : alert-pin-polarity alert-pin $(set) is                   $(bits-16 oldMask) to $(bits-16 newMask)"

  // Human readable alias for setting alert pin polarity
  alert-pin-polarity --inverted -> none:  alert-pin-polarity --set=1
  alert-pin-polarity --normal   -> none:  alert-pin-polarity --set=0

  // Retrieve configured alert pin polarity setting
  //
  alert-pin-polarity -> bool:
    // inverted = true, normal = false
    oldMask/int := reg_.read-u16-be INA226-REGISTER-MASK-ENABLE_
    polarityInverted/bool := false
    polarityInvertedBit/int := ((oldMask & INA226-ALERT-PIN-POLARITY-BIT) >> INA226-ALERT-PIN-POLARITY-OFFSET) & INA226-ALERT-PIN-POLARITY-LENGTH
    if polarityInvertedBit == 1: polarityInverted = true
    if debug_: print "*      : alert-pin-polarity is $(polarityInvertedBit) [$(polarityInverted)]"
    return polarityInverted

  // Alerts
  // NOTE:  Slightly different to the implementations I'd seen, I wanted alerts to
  //        be visible as a value on the class object, and not stored separately 
  //        from the source of truth.  So these functions attempt to source the current
  //        status of each alert from the device itself.
  
  // return true if any of the three alerts exists
  // NOTE:  done this way so that during debugging mode, the exact alert that triggered will be shown
  //        (more reads) whereas without debug mode, one read would suffice.
  alert -> bool:
    if debug_: 
      return overflow-alert or limit-alert or conversion-ready-alert
    else:
      register/int := reg_.read-u16-be INA226-REGISTER-MASK-ENABLE_
      checkMask    := INA226-ALERT-MATH-OVERFLOW-FLAG | INA226-ALERT-FUNCTION-FLAG | INA226-ALERT-CONVERSION-READY-FLAG
      return (register & checkMask) != 0

  // clear alerts
  alert --clear -> none:
    // Not Tested - manual suggests reading the MASK-ENABLE is enough to clear any alerts
    register/int := reg_.read-u16-be INA226-REGISTER-MASK-ENABLE_

  overflow-alert   -> bool:
    register/int := reg_.read-u16-be INA226-REGISTER-MASK-ENABLE_
    overflow := false
    overflowBit := ((register & INA226-ALERT-MATH-OVERFLOW-FLAG) >> INA226-ALERT-MATH-OVERFLOW-OFFSET ) & INA226-ALERT-MATH-OVERFLOW-LENGTH
    if overflowBit == 1: overflow = true
    if debug_: print "*      : alert: overflow bit is $(overflowBit) [$(overflow)]"
    return overflow

  limit-alert      -> bool:
    register/int := reg_.read-u16-be INA226-REGISTER-MASK-ENABLE_
    overflow := false
    overflowBit := ((register & INA226-ALERT-FUNCTION-FLAG) >> INA226-ALERT-FUNCTION-OFFSET ) & INA226-ALERT-FUNCTION-LENGTH
    if overflowBit == 1: overflow = true
    if debug_: print "*      : alert: configured limit bit is $(overflowBit) [$(overflow)]"
    return overflow

  // Determine If Conversion is Complete
  // Note:  Although the device can be read at any time, and the data from
  //        the last conversion is available, the Conversion Ready Flag bit is
  //        provided to help coordinate one-shot or triggered conversions. The 
  //        Conversion Ready Flag bit is set after all conversions, averaging, 
  //        and multiplications are complete. Conversion Ready Flag bit clears
  //        under the following conditions:
  //        1. Writing to the Configuration Register (except for Power-Down selection)
  //        2. Reading the Mask/Enable Register
  //
  conversion-ready-alert -> bool:
    register/int := reg_.read-u16-be INA226-REGISTER-MASK-ENABLE_
    conversionReady := false
    conversionReadyBit := ((register & INA226-ALERT-CONVERSION-READY-FLAG) >> INA226-ALERT-CONVERSION-READY-OFFSET ) & INA226-ALERT-CONVERSION-READY-LENGTH
    if conversionReadyBit == 1: conversionReady = true
    if debug_: print "*      : alert: conversion ready bit is $(conversionReadyBit) [$(conversionReady)]"
    return conversionReady

  // Alias for alert-conversion-ready
  //
  conversion-ready -> bool:
    return conversion-ready-alert
  
  // Configure the alert function enabling the pin to be used to signal conversion ready.
  //
  conversion-ready --set/int -> none:
    assert: 0 <= set <= 1
    oldMask/int := reg_.read-u16-be INA226-REGISTER-MASK-ENABLE_
    newMask/int := oldMask
    newMask     &= ~(INA226-CONVERSION-READY-BIT)
    newMask     |= (set << INA226-CONVERSION-READY-OFFSET) // already bit shifted
    reg_.write-u16-be INA226-REGISTER-MASK-ENABLE_ newMask
    if debug_: print "*      : conversion-ready alert-pin $(set) is                     $(bits-16 oldMask) to $(bits-16 newMask)"

  // Helpful alias for setting 'conversion-ready' on alert pin
  //
  conversion-ready --enable-alert-pin -> none:
    conversion-ready --set=1

  // Helpful alias for setting 'conversion-ready' on alert pin
  //
  conversion-ready --disable-alert-pin -> none:
    conversion-ready --set=0

  // Returns microsecs for INA226-TIMING-x-us statics 0..7
  // NOTE:  A helper function
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

  // Returns sample count for INA226-AVERAGE-x-SAMPLE statics 0..7
  // NOTE:  A helper function
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

  // Estimate a maximum waiting time based on the configuration
  // NOTE:  Done this way to prevent setting a global maxWait type
  //        value, to then have it fail based on times that are longer
  //        due to timing configurations 
  estimated-conversion-time --ms -> int:
    // Read config and decode fields using masks/offsets
    register/int    := reg_.read-u16-be INA226-REGISTER-CONFIG_

    samplesCode/int    := (register & INA226-CONF-AVERAGE-MASK)  >> INA226-CONF-AVERAGE-OFFSET
    busCTcode/int      := (register & INA226-CONF-BUSVC-MASK)    >> INA226-CONF-BUSVC-OFFSET
    shuntCTcode/int    := (register & INA226-CONF-SHUNTVC-MASK)  >> INA226-CONF-SHUNTVC-OFFSET
    mode/int           := (register & INA226-CONF-MODE-MASK)     >> INA226-CONF-MODE-OFFSET

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

    if debug_: print "*      : estimated-conversion-time --ms is: $(totalms)ms"
    return totalms

  // INFORMATION FUNCTIONS

  // Get Manufacturer/Die identifiers
  // NOTE:  maybe useful if expanding driver to suit an additional sibling device
  //
  manufacturer-id -> int:
    manid := reg_.read-u16-be INA226-REGISTER-MANUF-ID_
    if debug_: print "*      : manufacturer-id is 0x$(%04x manid) [$(manid)]"
    return manid
  
  // NOTE: Given DID and RID below, this value on its own may be redundant
  die-id -> int:
    dieid := reg_.read-u16-be INA226-REGISTER-DIE-ID_
    if debug_: print "*      : die-id register is 0x$(%04x dieid) [$(dieid)]"
    return dieid

  // Device ID Bits
  // NOTE:  Bits 4-15 Stores the device identification bits
  // 
  device-identification -> int:
    register := reg_.read-u16-be INA226-REGISTER-DIE-ID_
    dieidDid := (register & INA226-DIE-ID-DID-MASK) >> 4
    if debug_: print "*      : die-id DID is      0x$(%04x dieidDid) [$(dieidDid)]"
    return dieidDid

  // Die Revision ID Bits
  // NOTE:  Bit 0-3 Stores the device revision identification bits
  //
  device-revision -> int:
    register := reg_.read-u16-be INA226-REGISTER-DIE-ID_
    dieidRid := (register & INA226-DIE-ID-RID-MASK)
    if debug_: print "*      : die-id RID is      0x$(%04x dieidRid) [$(dieidRid)]"
    return dieidRid

  // TROUBLESHOOTING FUNCTIONS

  // Infer Shunt Resistor using a known load resistor
  // NOTE:  Averages a few samples for stability, ensures both voltages come from the
  //        same conversion, and returns the estimated shunt value.
  // NOTE:  On Accuracy:
  //        - Known load tolerance dominates: use a 0.1–1% resistor if possible
  //        - Make sure VBUS & load node (IN−) are tied
  //        - Kelvin the shunt if possible: sense pins at the shunt pads
  //        - Perform test/readings after the load settles - average some samples
  //        - Low-current corner: if Vshunt is just a few tens of µV, quantization/noise
  //          can move the estimate; use a load that draws a few mA+ to get a clean mV-level Vsh.
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
    print "Infer shunt: Vload=$(loadVoltage) V  Vsh=$(shuntVoltage) V  Rload=$(loadResistor) Ohm  -> I=$(currentEstimate)A  Rsh_est=$(shuntResistorEstimate) Ohm"
    return shuntResistorEstimate

  // Determine shunt resistor value from known load
  // NOTE:  See notes above for similar function.
  //        Useful if you have a DMM clamp or source  
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
    print "Infer shunt: Vsh=$(shuntVoltage)V  I_known=$(loadCurrent)A  -> Rsh_est=$(shuntResistorEstimate)Ω"
    return shuntResistorEstimate


  // Determine VBUS and VLOAD are different
  // NOTE:  Evaluates if the bus and load voltages are different (eg not tied).
  //        Useful for diagnostic functions only.  If the voltages are the same,
  //        it is not proof that they are tied, this attempts to check for the
  //        simple case where values indiate it is not tied.
  //
  verify-tied-bus-load -> bool:
    // Optional: ensure fresh data
    single-measurement
    wait-until-conversion-completed

    busVoltage/float := bus-voltage --volts
    loadVoltage/float := load-voltage --volts
    busLoadDelta/float := (busVoltage - loadVoltage).abs
  
    if debug_: print "Bus = $(%0.8f busVoltage)V, Load = $(%0.8f loadVoltage)V, Delta = $(%0.8f busLoadDelta)V"
    if busLoadDelta < 0.01:       // <10 mV difference
      if debug_: print " Bus and load values appear the same (tied?)     Delta=$(%0.8f busLoadDelta)V"
      return true
    else if busLoadDelta < 0.05:  // 10–50 mV: maybe wiring drop
      if debug_: print " Bus/load differ slightly (check traces/wiring)  Delta=$(%0.8f busLoadDelta)V"
      return false
    else:
      if debug_: print " Bus and load differ significantly (not tied)    Delta=$(%0.8f busLoadDelta)V"
      return false

  // Print Diagnostic Information
  // NOTE:  Prints relevant measurement information to allow someone with a
  //        Voltmeter to double check what is measured and compare it.  Also
  //        calculates/compares using Ohms Law (V=I*R)
  //
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
    currentRaw/int                   := reg_.read-i16-be INA226-REGISTER-SHUNT-CURRENT_
    leastSignificantBit/float        := 0.00512 / (calibrationValue.to-float * shuntResistor_)
    currentChip/float                := currentRaw * leastSignificantBit
    currentVR/float                  := shuntVoltage / shuntResistor_

    // CROSSCHECK: between chip/measured current and V/R reconstructed current
    currentDifference/float          := (currentChip - currentVR).abs
    currentDifferencePct/float       := 0.0
    if (currentVR != 0.0): 
      currentDifferencePct           = (currentDifference / currentVR) * 100.0

    // CROSSCHECK: shunt voltage (measured vs reconstructed)
    shuntVoltageCalculated/float     := currentChip * shuntResistor_
    shuntVoltageDifference/float     := (shuntVoltage - shuntVoltageCalculated).abs
    shuntVoltageDifferencePct/float  := 0.0
    if (shuntVoltage != 0.0): 
      shuntVoltageDifferencePct      = (shuntVoltageDifference / shuntVoltage).abs * 100.0

    print "DIAG :"
    print "    ----------------------------------------------------------"
    print "    Shunt Resistor    =  $(%0.8f shuntResistor_) Ohm (Configured in code)"
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

  // Helper Function for displaying bitmasks nicely
  //
  bits-16 x/int -> string:
    outStr := "$(%b x)"
    outStr = outStr.pad --left 16 '0'
    outStr = "$(outStr[0..4]).$(outStr[4..8]).$(outStr[8..12]).$(outStr[12..16])"
    return outStr

/*

void INA226-WE::setCurrentRange(INA226-CURRENT-RANGE range){ // deprecated, left for downward compatibility
    deviceCurrentRange = range    
}

*/
