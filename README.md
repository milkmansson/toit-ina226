# Toit Library for a TI INA226 Voltage/Current Measurement Mmodule
Toit Driver Library for an INA226 module, DC Shunt Current, Voltage, and Power Monitor

## About the Device
The INA226 from Texas Instruments is a precision digital power monitor with an integrated 16-bit ADC.  It measures the voltage drop across a shunt resistor to calculate current, monitors the bus voltage directly, and internally multiplies the two to report power consumption.

Core features:
- Measures shunt voltage (±81.92 mV) with 2.5 uV resolution.
- Measures bus voltage (0 – 36 V) with 1.25 mV resolution.
- Shunt voltage: 2.5 uV/LSB, full-scale ±81.92 mV. 
- Bus voltage: 1.25 mV/LSB, full-scale code = 40.96 V (but input must be ≤36 V). 
- Computes current and power using a user-programmable shunt resistor value and calibration register (Current and Power are 0 until this is set.)
- Independent conversion times for bus and shunt channels (140 us – 8.3 ms).
- Programmable averaging (1 – 1024 samples) for noise reduction.
- I²C interface - Fast (≤400 kHz) and High-Speed mode up to 2.94 MHz
- Built-in alert system for over/under-voltage, over-current, over-power, and conversion ready.
- Operates from a single 2.7 – 5.5 V supply.

The INA226 device is cheap enough, and suited for power monitoring of small devices like microcontrollers, sensors, and IoT or embedded systems loads.  Many modules come with a R100 shunt resistor onboard, but this can be desoldered and changed, and new values assigned when the driver is used. 

Further information can be found about this device here:
- [ESPHome description of the device](https://esphome.io/components/sensor/ina226/)
- [Module datasheet from Texas Instruments](https://www.ti.com/lit/ds/symlink/ina226.pdf)

There are several modules cheaply available based on this chipset.

## About this library
This library begun as a port of work originally done by Wolfgang Ewald <WEwald@gmx.de>.  [Originally published on Github](https://github.com/wollewald/INA226_WE).  Since then, through testing and other development, has gained some extra functionality: 
- Testing functions to help
  - Report significant values to compare against voltmeter measures to determine accuracy
  - Reverse engineer known loads to confirm accuracy of the Shunt resistor value
  - Extra functions to report information useful in debugging
- Calculation of values for timeouts (instead of the 'max-wait' hard coded values)
- Using of overloads to help make the code simpler for each feature required
- Extra aliases for reads to help unfamiliar users get started with this


# Usage
Start with the [Quick Start] or start with the core concepts.

## Core Concepts

#### History
“Shunt” comes from the verb to shunt, meaning to divert or to bypass.  In railway terms, a shunting line diverts trains off the main track.  In electrical engineering, a shunt resistor is used to divert current into a measurable path.

Originally, in measurement circuits, shunt resistors were used in analog ammeters.  A sensitive meter with sensitive needle movement could only handle very tiny current.  A low-value “shunt” resistor was therefore placed in parallel to bypass (or shunt) most of the current, so the meter only saw a safe fraction.  By calibrating the ratio, read large currents could be read with a small meter.

#### How it works
The INA226 measures current using a tiny precision resistor (referred to in the code as a shunt resistor) placed in series with the load. 
When current flows through the shunt, a small voltage develops across it (Ohm’s Law: V = I × R). Because the resistance is very low (for example 0.1 Ohm), this voltage is only a few millivolts even at significant currents, which minimizes power loss in the measurement path.  The INA226’s high-resolution ADC is designed to sense this tiny voltage drop. (microvolt precision)

Simultaneously, the device monitors the bus voltage on the load side of the shunt. By combining the shunt voltage (for current) with the bus voltage (for supply level), the INA226 can also compute power consumption internally.  These values are stored in registers and can be retrieved over I²C. Configurable conversion times and averaging allow the trade-off between faster updates or lower noise, making the device flexible for both low-power IoT nodes and higher-current embedded systems.

This means the INA226 can be configured to trade off:
- *Speed*: If quick updates are needed (e.g. sampling a fast-changing load) shorter conversion times are required.
- vs. *Accuracy/noise rejection*: If very small currents are being measured (tiny shunt voltages), longer conversion times are required to average out noise.

#### Measuring/Operating Modes
The device has two measuring modes: Continuous and Triggered.

###### Continuous Mode
In continuous mode, the INA226 loops forever:
- It repeatedly measures bus voltage and shunt voltage.
- Each conversion result overwrites the previous one in the registers.
- The sampling cadence is set by your conversion times + averaging settings.
- Typical current draw is 330uA typical, 420 uA max.

Use cases:
- Requiring a live stream of current/voltage/power, e.g. logging consumption of an IoT node over hours.
- In cases where the MCU needs to poll for measurements periodically, & expects the register to always hold the freshest value.
- Best for steady-state loads or long-term monitoring.

###### Triggered Mode
In triggered (single-shot) mode:
- The INA226 sits idle until a measurement is explicitly triggered (by writing to the config register).
- It performs exactly one set of conversions (bus + shunt, with averaging if configured).
- Then it goes back to idle (low power).
- Each conversion uses ~330 uA during its active time (typically a few milliseconds).

Use cases:
- Low power consumption: e.g. wake up the INA226 once every few seconds/minutes, take a measurement, then let both the INA226 and MCU sleep.
- Synchronized measurement: e.g. where a measurement is necessary at the same time a load is toggled, eg, so the measurement can be triggered at the right time after.
- Useful in battery-powered applications where quiescent drain must be minimized.

##### Power-Down Mode
INA226 enters ultra-low-power state. No measurements happen. Supply current drops to 0.5 uA typ (2uA max). Useful for ultra-low power systems where periodic measurement isn't needed.

#### Conversion Time
The INA226 has an ADC (Analog-to-Digital Converter) inside.
- measures shunt voltage (across IN+ and IN–).
- measures bus voltage (IN– relative to GND).
- Each of these conversions takes some time, depending on how many internal samples are averaged.
The conversion time setting tells the ADC how long to spend on a single measurement of either the shunt voltage or the bus voltage.
- Longer time = more samples averaged inside = less noise, higher resolution.
- Shorter time = fewer samples = faster updates, but noisier.

Waiting time (estimated conversion time) is calculated using:
- Shunt conversion time
- Bus conversion time
- Number of samples in an average measurement (steps through 1–1024, see code)
- Then adding ~10% guard margin

Technically: 
- Bus conversion time → how long the INA226 spends converting the bus voltage (VBUS = IN− relative to GND).
- Shunt conversion time → how long it spends converting the shunt voltage (VSH = IN+ – IN−).
- Current isn’t measured directly — it’s computed later from Vshunt ÷ Rshunt.

#### Measurement Functions
The INA226 measures two things natively:
1. Vshunt = IN+ - IN-  (a small differential voltage across your shunt)
2. Vbus   = the “bus/load” node voltage (most breakouts tie VBUS to IN−)

From these, the driver computes current and power, and reconstructs the upstream supply.  Typical wiring on breakout boards: VBUS is internally tied to IN− (the low side of the shunt).  If your hardware is different (VBUS not tied to IN−), the meanings below still hold, but “bus voltage” is whatever is wired to VBUS. Most users only connect IN+ and IN−, which is sufficient for the readings shown.

Units and scaling:
- read-shunt-voltage:     volts (V).    LSB ≈ 2.5 uV internally.
- read-bus-voltage:       volts (V).    LSB ≈ 1.25 mV internally.
- read-shunt-current:     amps (A).     Derived from Vshunt and configured shunt resistor (calibration)
- read-load-power:        watts (W).    Derived internally by the chip from current*25*LSB.
- read-supply-voltage:    volts (V).    Reconstructed as Vbus + Vshunt.

read-shunt-voltage -> float
What it is:    The tiny voltage drop across your shunt: Vshunt = IN+ − IN−.
Why you care:  It’s the raw signal that indicates load current (Ohm’s law: I = Vshunt / Rshunt).
Typical magnitude:  Millivolts (mV) or tens/hundreds of microvolts at low current.
Caveats: Sensitive to noise; use higher averaging/conversion time for stability.

read-bus-voltage -> float
What it is: The “load node” voltage. On most modules this is the same node as IN− i.e., what the load actually sees as its supply rail after the shunt.
Why you care: It’s the real supply presented to your device-under-test (after shunt drop).
Caveats: If your board does not tie VBUS to IN−, this returns whatever VBUS is wired to.

read-supply-voltage -> float
What it is: The upstream/source voltage *before* the shunt, reconstructed as: Vsupply ≈ Vbus + Vshunt = (voltage at IN−) + (IN+ − IN−) = voltage at IN+.
Why you care:  Lets you see the source rail while only wiring IN+ and IN−.
Caveats:
- Assumes the usual low-side sense where Vbus reflects the IN− node.
- For high currents, Vshunt may be a few to tens of mV; this adds directly.

read-shunt-current -> float
What it is: The current through the shunt and your load, in amps.
How it’s obtained: Internally, the chip uses a calibration constant set from your configured shunt.
Conceptually: I ≈ Vshunt / Rshunt (the driver scales the chip’s current register).
Why you care: Primary measurement for load current.
Caveats:
- Accurate only if shunt value in code matches your physical shunt.
- Choose appropriate averaging/conversion time for the dynamic you need.

read-load-power -> float
What it is: Power delivered to the load (approx. Vbus * I), in watts.
How it’s obtained: Uses the INA226 power register (which multiplies measured current by an internal factor).
Why you care: One-call view of how much power your device is drawing.
Caveats:
- Because Vbus is after the shunt, this approximates power at the load (not at the source).
- Depends on correct calibration (shunt value).


#### Alerting
The INA226 includes a flexible alert system that can drive an external pin, and/or be read in software.  Alerts can be configured for several conditions, such as over- or under-voltage (on the shunt or bus), over-current or over-power.  Additionally, it can be configured to trigger on 'conversion-ready' - a flag indicating that new data is available.  Only one alert function can be active at a time since the alert pin is shared.  
The configuration registers allow thresholds to be set, configure alert latching behavior, and choose the alert pin polarity.  Because the alert mechanism is evaluated against the most recent ADC conversion, its response time is limited by the selected conversion times and averaging settings: longer averaging means more stable results but slower alerts.  This makes the feature most useful for catching sustained fault conditions (like over-current or brownout), rather than extremely fast transients.


## Quick Start Information
The following steps should get you operational quickly:
- Follow Wiring Diagrams to get the device connected correctly.
- Ensure Toit is installed on your ESP32 and operating.  (Most of the code examples require the use `jag monitor` to show outputs.)  See Toit Documentation to get started.
- This is a device using I2C, Toit documentation has a great explainer/examples.
- Get a code example to see an example of obtaining the various registers and values.

## Detailed Information
In order for this device to work, several things are done in code:
- Setting of a conversion value 

## Changing the Shunt Resistor
Many cheap INA226 modules ship with 0.1 Ω or 0.01 Ω shunts.
- For high-current applications (tens of amps), the shunt can be replaced with a much smaller value (e.g. 1–5 mΩ). This reduces voltage drop and wasted power, and raises the maximum measurable current, but makes the resolution for tiny currents coarser.
- For low-current applications (milliamps), a larger shunt (e.g. 0.5–1.0 Ω) increases sensitivity and resolution, but lowers the maximum measurable current (≈80 mA with a 1 Ω shunt) and burns more power in the resistor itself.
**IMPORTANT:** Always update the calibration constant in the code after changing the shunt. The INA226 does not store these values permanently.

# About Toit
One would assume you are here because you know what Toit is.  If you dont:

# Credits
- Wolfgang (Wolle) Ewald <WEwald@gmx.de> for the original code [published here](https://github.com/wollewald/INA226_WE)
  - https://wolles-elektronikkiste.de/en/ina226-current-and-power-sensor (English)
  - https://wolles-elektronikkiste.de/ina226 (German)
- Rob Tillaart's work [here](https://github.com/RobTillaart/INA226) which helped me understand and correct the work
- [Florian](https://github.com/floitsch) for the tireless help and encouragement
- The wider Toit developer team (past and present) for a truly excellent product
