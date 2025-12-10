;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;   Modular Simulator Controller System - AI Strategy Generator           ;;;
;;;                                                                         ;;;
;;;   Author:     Alejandro Castilla Quesada                                ;;;
;;;   License:    (2025) Creative Commons - BY-NC-SA                        ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;-------------------------------------------------------------------------;;;
;;;                       Global Declaration Section                        ;;;
;;;-------------------------------------------------------------------------;;;

;@SC-IF %configuration% == Development
#Include "..\Framework\Development.ahk"
;@SC-EndIF

;@SC-If %configuration% == Production
;@SC #Include "..\Framework\Production.ahk"
;@SC-EndIf

;@Ahk2Exe-SetMainIcon ..\..\Resources\Icons\Workbench.ico
;@Ahk2Exe-ExeName AI Strategy Generator.exe
;@Ahk2Exe-SetCompanyName Alejandro Castilla
;@Ahk2Exe-SetCopyright Creative Commons - BY-NC-SA
;@Ahk2Exe-SetProductName Simulator Controller
;@Ahk2Exe-SetVersion 0.0.0.0


;;;-------------------------------------------------------------------------;;;
;;;                         Global Include Section                          ;;;
;;;-------------------------------------------------------------------------;;;

#Include "..\Framework\Application.ahk"


;;;-------------------------------------------------------------------------;;;
;;;                         Local Include Section                           ;;;
;;;-------------------------------------------------------------------------;;;

#Include "..\Framework\Extensions\Messages.ahk"
#Include "..\Framework\Extensions\CLR.ahk"
#Include "..\Framework\Extensions\LLMConnector.ahk"
#Include "..\Database\Libraries\LapsDatabase.ahk"
#Include "..\Database\Libraries\SessionDatabase.ahk"
#Include "..\Plugins\Libraries\SimulatorProvider.ahk"


;;;-------------------------------------------------------------------------;;;
;;;                        Private Constant Section                         ;;;
;;;-------------------------------------------------------------------------;;;

global kOk := "Ok"
global kCancel := "Cancel"


;;;-------------------------------------------------------------------------;;;
;;;                         Private Classes Section                         ;;;
;;;-------------------------------------------------------------------------;;;

class StrategyGenerator extends ConfigurationItem {
	static Instance := false

	iWindow := false
	iClosed := false

	iSimulators := []
	iCars := []
	iTracks := []
	iWeathers := []
	iCompounds := []

	iSelectedSimulator := false
	iSelectedCar := false
	iSelectedTrack := false
	iSelectedWeather := "Dry"
	iAirTemperature := 23
	iTrackTemperature := 27

	class SimpleLLMManager {
		iConfiguration := false

		Configuration {
			Get {
				return this.iConfiguration
			}
		}

		__New(configuration) {
			this.iConfiguration := configuration
		}

		getInstructions() {
			return []
		}

		getTools(type := false) {
			return []
		}

		connectorState(state := false, type := false, info := false) {
			if (state = "Error") {
				if isDebug()
					logMessage(kLogWarn, "LLM Connector Error - Type: " . type . ", Info: " . (info ? info : "N/A"))
			}
		}
	}

	Window {
		Get {
			return this.iWindow
		}
	}

	Closed {
		Get {
			return this.iClosed
		}
	}

	SelectedSimulator {
		Get {
			return this.iSelectedSimulator
		}
	}

	SelectedCar {
		Get {
			return this.iSelectedCar
		}
	}

	SelectedTrack {
		Get {
			return this.iSelectedTrack
		}
	}

	SelectedWeather {
		Get {
			return this.iSelectedWeather
		}
	}

	AirTemperature {
		Get {
			return this.iAirTemperature
		}
	}

	TrackTemperature {
		Get {
			return this.iTrackTemperature
		}
	}

	__New() {
		global kSimulatorConfiguration

		super.__New(kSimulatorConfiguration)

		StrategyGenerator.Instance := this
	}

	createGui() {
		local aiGui, x, y, w1, w2, w3, labelWidth, editWidth
		local simulator, car, track
		local choices

		aiGui := Window({Descriptor: "AI Strategy Generator", Options: "0x400000"}, translate("AI Strategy Generator"))

		this.iWindow := aiGui

		aiGui.SetFont("s10 Bold", "Arial")

		aiGui.Add("Text", "x16 y16 w760 Center", translate("AI Strategy Generator"))

		aiGui.SetFont("s9 Norm", "Arial")

		; Section 1: Session Information
		aiGui.SetFont("s9 Bold", "Arial")
		aiGui.Add("GroupBox", "x16 y50 w760 h180", translate("Session Information"))
		aiGui.SetFont("s8 Norm", "Arial")

		labelWidth := 120
		editWidth := 200

		; Row 1: Simulator and Car
		aiGui.Add("Text", "x32 y75 w" . labelWidth, translate("Simulator"))
		aiGui.Add("DropDownList", "x160 y72 w" . editWidth . " VsimulatorDropDown", [translate("Select Simulator...")]).OnEvent("Change", (*) => this.loadSimulatorData())

		aiGui.Add("Text", "x400 y75 w" . labelWidth, translate("Car"))
		aiGui.Add("DropDownList", "x528 y72 w" . editWidth . " VcarDropDown Disabled", [translate("Select Car...")])

		; Row 2: Track and Weather
		aiGui.Add("Text", "x32 y105 w" . labelWidth, translate("Track"))
		aiGui.Add("DropDownList", "x160 y102 w" . editWidth . " VtrackDropDown Disabled", [translate("Select Track...")])

		aiGui.Add("Text", "x400 y105 w" . labelWidth, translate("Weather"))
		choices := collect(["Dry", "Drizzle", "LightRain", "MediumRain", "HeavyRain", "Thunderstorm"], translate)
		aiGui.Add("DropDownList", "x528 y102 w" . editWidth . " Choose1 VweatherDropDown", choices).OnEvent("Change", (*) => this.updateWeather())

		; Row 3: Temperatures
		aiGui.Add("Text", "x32 y135 w" . labelWidth, translate("Air Temperature (°C)"))
		aiGui.Add("Edit", "x160 y132 w80 Number VairTempEdit", "23")

		aiGui.Add("Text", "x400 y135 w" . labelWidth, translate("Track Temperature (°C)"))
		aiGui.Add("Edit", "x528 y132 w80 Number VtrackTempEdit", "27")

		; Row 4: Session Type and Length
		aiGui.Add("Text", "x32 y165 w" . labelWidth, translate("Session Type"))
		aiGui.Add("DropDownList", "x160 y162 w" . editWidth . " Choose1 VsessionTypeDropDown", collect(["Duration", "Laps"], translate))

		aiGui.Add("Text", "x400 y165 w" . labelWidth, translate("Session Length"))
		aiGui.Add("Edit", "x528 y162 w80 Number VsessionLengthEdit", "60")
		aiGui.Add("Text", "x620 y165", translate("(minutes or laps)"))

		; Section 2: Race Rules
		aiGui.SetFont("s9 Bold", "Arial")
		aiGui.Add("GroupBox", "x16 y210 w760 h210", translate("Race Rules"))
		aiGui.SetFont("s8 Norm", "Arial")

		; Row 1: Formation and Post-Race Laps
		aiGui.Add("CheckBox", "x32 y235 w200 VformationLapCheck", translate("Formation Lap"))
		aiGui.Add("CheckBox", "x250 y235 w200 VpostRaceLapCheck", translate("Post-Race Lap"))

		; Row 2: Pitstop Rules
		aiGui.Add("Text", "x32 y265 w" . labelWidth, translate("Pitstop Rule"))
		choices := collect(["Variable", "Fixed"], translate)
		aiGui.Add("DropDownList", "x160 y262 w" . editWidth . " Choose1 VpitstopRuleDropDown", choices).OnEvent("Change", (*) => this.updatePitstopRule())

		aiGui.Add("Text", "x400 y265 w" . labelWidth, translate("Required Pitstops"))
		aiGui.Add("Edit", "x528 y262 w80 Number Disabled VrequiredPitstopsEdit", "1")

		; Row 3: Pitstop Window
		aiGui.Add("CheckBox", "x32 y295 w" . labelWidth . " VpitstopWindowCheck", translate("Pitstop Window")).OnEvent("Click", (*) => this.updatePitstopWindow())
		aiGui.Add("Text", "x160 y298 w40", translate("From"))
		aiGui.Add("Edit", "x200 y295 w60 Number Disabled VpitstopWindowFromEdit", "1")
		aiGui.Add("Text", "x270 y298 w20", translate("To"))
		aiGui.Add("Edit", "x295 y295 w60 Number Disabled VpitstopWindowToEdit", "999")

		; Row 4: Refuel and Tyre Change Requirements
		aiGui.Add("Text", "x32 y325 w" . labelWidth, translate("Refuel Requirement"))
		choices := collect(["Required", "Optional", "Not Allowed"], translate)
		aiGui.Add("DropDownList", "x160 y322 w" . editWidth . " Choose1 VrefuelDropDown", choices)

		aiGui.Add("Text", "x400 y325 w" . labelWidth, translate("Tyre Change"))
		choices := collect(["Required", "Optional", "Not Allowed"], translate)
		aiGui.Add("DropDownList", "x528 y322 w" . editWidth . " Choose1 VtyreChangeDropDown", choices)

		; Row 5: Validator
		aiGui.Add("Text", "x32 y355 w" . labelWidth, translate("Strategy Validator"))
		choices := [translate("None"), "FIA F1", "FIA F2", "FIA F3", "IMSA GT3", "GT World Challenge"]
		aiGui.Add("DropDownList", "x160 y352 w" . editWidth . " Choose1 VvalidatorDropDown", choices)

		; Row 6: Available Compounds
		aiGui.Add("Text", "x32 y385 w" . labelWidth, translate("Available Compounds"))
		aiGui.Add("Edit", "x160 y382 w536 ReadOnly VcompoundsDisplayEdit", "")

		; Row 7: Tyre Sets
		aiGui.Add("Text", "x32 y415 w700", translate("Tyre Sets (format: Compound|Color|Count|MaxLaps; e.g., Dry|Black|2|30;Dry|White|1|25)"))
		aiGui.Add("Edit", "x32 y432 w696 VtyreSetsEdit")

		; Section 3: Technical Settings
		aiGui.SetFont("s9 Bold", "Arial")
		aiGui.Add("GroupBox", "x16 y460 w760 h180", translate("Technical Settings"))
		aiGui.SetFont("s8 Norm", "Arial")

		; Row 1: Fuel Capacity and Safety Fuel
		aiGui.Add("Text", "x32 y485 w" . labelWidth, translate("Fuel Capacity (L)"))
		aiGui.Add("Edit", "x160 y482 w80 Number VfuelCapacityEdit", "120")

		aiGui.Add("Text", "x400 y485 w" . labelWidth, translate("Safety Fuel (L)"))
		aiGui.Add("Edit", "x528 y482 w80 Number VsafetyFuelEdit", "3")

		; Row 2: Pitstop Delta
		aiGui.Add("Text", "x32 y515 w" . labelWidth, translate("Pitstop Delta (s)"))
		aiGui.Add("Edit", "x160 y512 w80 Number VpitstopDeltaEdit", "30")

		; Row 3: Fuel Service
		aiGui.Add("Text", "x32 y545 w" . labelWidth, translate("Fuel Service"))
		choices := collect(["Simultaneous", "Before Tyres", "After Tyres"], translate)
		aiGui.Add("DropDownList", "x160 y542 w" . editWidth . " Choose1 VfuelServiceDropDown", choices)

		aiGui.Add("Text", "x400 y545 w" . labelWidth, translate("Refuel Rate (L/s)"))
		aiGui.Add("Edit", "x528 y542 w80 Number VrefuelRateEdit", "2.0")

		; Row 4: Tyre Service
		aiGui.Add("Text", "x32 y575 w" . labelWidth, translate("Tyre Service Time (s)"))
		aiGui.Add("Edit", "x160 y572 w80 Number VtyreServiceEdit", "3")

		; Row 5: Service Order
		aiGui.Add("Text", "x32 y605 w" . labelWidth, translate("Service Order"))
		choices := collect(["Simultaneous", "Tyre => Refuel", "Refuel => Tyre"], translate)
		aiGui.Add("DropDownList", "x160 y602 w" . editWidth . " Choose1 VserviceOrderDropDown", choices)

		; Section 4: Additional Context
		aiGui.SetFont("s9 Bold", "Arial")
		aiGui.Add("GroupBox", "x16 y650 w760 h100", translate("Additional Context"))
		aiGui.SetFont("s8 Norm", "Arial")

		aiGui.Add("Text", "x32 y675 w700", translate("Notes (optional context for AI strategist)"))
		aiGui.Add("Edit", "x32 y692 w696 h45 VnotesEdit")

		; Action Buttons
		aiGui.Add("Button", "x280 y765 w100 h30", translate("Generate")).OnEvent("Click", (*) => this.generateStrategy())
		aiGui.Add("Button", "x400 y765 w100 h30", translate("Close")).OnEvent("Click", (*) => this.close())

		aiGui.OnEvent("Close", (*) => this.close())
		aiGui.OnEvent("Escape", (*) => this.close())

		this.loadSimulators()
	}

	loadSimulators() {
		local simulatorDropDown := this.Window["simulatorDropDown"]
		local simulators := []
		local ignore, simulator

		for ignore, simulator in SessionDatabase.getSimulators()
			simulators.Push(simulator)

		this.iSimulators := simulators

		if (simulators.Length > 0) {
			simulatorDropDown.Delete()
			simulatorDropDown.Add(simulators)
			simulatorDropDown.Choose(1)

			this.loadSimulatorData()
		}
	}

	loadSimulatorData() {
		local simulatorDropDown := this.Window["simulatorDropDown"]
		local carDropDown := this.Window["carDropDown"]
		local trackDropDown := this.Window["trackDropDown"]
		local sessionDB := SessionDatabase()
		local cars := []
		local tracks := []
		local ignore, car, track

		if (simulatorDropDown.Value > 0) {
			this.iSelectedSimulator := this.iSimulators[simulatorDropDown.Value]

			; Load cars
			for ignore, car in sessionDB.getCars(this.iSelectedSimulator)
				cars.Push(car)

			this.iCars := cars

			; Update car dropdown
			carDropDown.Delete()
			if (cars.Length > 0) {
				carDropDown.Add(cars)
				carDropDown.Enabled := true
				carDropDown.Choose(1)
				this.iSelectedCar := cars[1]

				; Add onChange handler for car dropdown
				carDropDown.OnEvent("Change", (*) => this.updateCar())

				; Load tracks for the first car
				for ignore, track in sessionDB.getTracks(this.iSelectedSimulator, this.iSelectedCar)
					tracks.Push(track)

				this.iTracks := tracks
			}

			; Update track dropdown
			trackDropDown.Delete()
			if (tracks.Length > 0) {
				trackDropDown.Add(tracks)
				trackDropDown.Enabled := true
				trackDropDown.Choose(1)
				this.iSelectedTrack := tracks[1]

				; Add onChange handler for track dropdown
				trackDropDown.OnEvent("Change", (*) => this.updateTrack())

				; Load compounds for initial selection
				this.loadTyreCompounds()
			}
		}
	}

	updateCar() {
		local carDropDown := this.Window["carDropDown"]
		local trackDropDown := this.Window["trackDropDown"]
		local sessionDB := SessionDatabase()
		local tracks := []
		local ignore, track

		if (carDropDown.Value > 0) {
			this.iSelectedCar := this.iCars[carDropDown.Value]

			; Reload tracks for this car
			for ignore, track in sessionDB.getTracks(this.iSelectedSimulator, this.iSelectedCar)
				tracks.Push(track)

			this.iTracks := tracks

			trackDropDown.Delete()
			if (tracks.Length > 0) {
				trackDropDown.Add(tracks)
				trackDropDown.Choose(1)
				this.iSelectedTrack := tracks[1]

				; Load compounds for new car/track combination
				this.loadTyreCompounds()
			}
		}
	}

	updateTrack() {
		local trackDropDown := this.Window["trackDropDown"]

		if (trackDropDown.Value > 0) {
			this.iSelectedTrack := this.iTracks[trackDropDown.Value]

			; Load compounds for new track
			this.loadTyreCompounds()
		}
	}

	loadTyreCompounds() {
		local compounds := SessionDatabase().getTyreCompounds(this.iSelectedSimulator, this.iSelectedCar, this.iSelectedTrack)
		local compoundsDisplay := ""
		local ignore, compound

		this.iCompounds := compounds

		; Update the compounds display field
		if (compounds && compounds.Length > 0) {
			for ignore, compound in compounds {
				if (compoundsDisplay != "")
					compoundsDisplay .= ", "
				compoundsDisplay .= compound
			}
			this.Window["compoundsDisplayEdit"].Text := compoundsDisplay
		}
		else {
			this.Window["compoundsDisplayEdit"].Text := ""
		}
	}

	updateWeather() {
		local weatherDropDown := this.Window["weatherDropDown"]
		local weathers := ["Dry", "Drizzle", "LightRain", "MediumRain", "HeavyRain", "Thunderstorm"]

		if (weatherDropDown.Value > 0)
			this.iSelectedWeather := weathers[weatherDropDown.Value]
	}

	updatePitstopRule() {
		local pitstopRuleDropDown := this.Window["pitstopRuleDropDown"]
		local requiredPitstopsEdit := this.Window["requiredPitstopsEdit"]

		if (pitstopRuleDropDown.Value = 2) { ; Fixed
			requiredPitstopsEdit.Enabled := true
		}
		else {
			requiredPitstopsEdit.Enabled := false
		}
	}

	updatePitstopWindow() {
		local pitstopWindowCheck := this.Window["pitstopWindowCheck"]
		local pitstopWindowFromEdit := this.Window["pitstopWindowFromEdit"]
		local pitstopWindowToEdit := this.Window["pitstopWindowToEdit"]

		if (pitstopWindowCheck.Value) {
			pitstopWindowFromEdit.Enabled := true
			pitstopWindowToEdit.Enabled := true
		}
		else {
			pitstopWindowFromEdit.Enabled := false
			pitstopWindowToEdit.Enabled := false
		}
	}

	generateStrategy() {
		local simulator := this.iSelectedSimulator
		local car := this.iSelectedCar
		local track := this.iSelectedTrack
		local weather := this.iSelectedWeather
		local airTemp, trackTemp, sessionType, sessionLength
		local lapsDB, tyreEntries, prompt, service, model, connector, response, manager
		local ignore, entry, dataJSON, filteredEntry, field
		local rules, settings, validator, pitstopRule, requiredPitstops, pitstopWindow
		local refuelRule, tyreChangeRule, tyreSets
		local formationLap, postRaceLap, fuelCapacity, safetyFuel, pitstopDelta
		local fuelService, refuelRate, tyreService, serviceOrder
		local pitstopWindowFrom, pitstopWindowTo
		local tyreSetList, tyreSetEntry, parts
		local compoundSpec, compoundName, compoundColor, tempTyreEntries
		local notes

		if (!simulator || !car || !track) {
			OnMessage(0x44, translateOkButton)
			withBlockedWindows(MsgBox, translate("Please select a Simulator, Car, and Track first."), translate("Warning"), 262192)
			OnMessage(0x44, translateOkButton, 0)
			return
		}

		if (!this.iCompounds || this.iCompounds.Length = 0) {
			OnMessage(0x44, translateOkButton)
			withBlockedWindows(MsgBox, translate("No tyre compounds available for this car/track combination."), translate("Warning"), 262192)
			OnMessage(0x44, translateOkButton, 0)
			return
		}

		try {
			; Get all values from GUI
			airTemp := this.Window["airTempEdit"].Text
			trackTemp := this.Window["trackTempEdit"].Text
			sessionType := (this.Window["sessionTypeDropDown"].Value = 1) ? "Duration" : "Laps"
			sessionLength := this.Window["sessionLengthEdit"].Text

			this.iAirTemperature := airTemp
			this.iTrackTemperature := trackTemp

			; Get race rules
			formationLap := this.Window["formationLapCheck"].Value
			postRaceLap := this.Window["postRaceLapCheck"].Value
			pitstopRule := this.Window["pitstopRuleDropDown"].Value
			requiredPitstops := this.Window["requiredPitstopsEdit"].Text
			pitstopWindow := this.Window["pitstopWindowCheck"].Value
			pitstopWindowFrom := this.Window["pitstopWindowFromEdit"].Text
			pitstopWindowTo := this.Window["pitstopWindowToEdit"].Text
			refuelRule := this.Window["refuelDropDown"].Value
			tyreChangeRule := this.Window["tyreChangeDropDown"].Value
			validator := this.Window["validatorDropDown"].Value
			tyreSets := this.Window["tyreSetsEdit"].Text

			; Get technical settings
			fuelCapacity := this.Window["fuelCapacityEdit"].Text
			safetyFuel := this.Window["safetyFuelEdit"].Text
			pitstopDelta := this.Window["pitstopDeltaEdit"].Text
			fuelService := this.Window["fuelServiceDropDown"].Value
			refuelRate := this.Window["refuelRateEdit"].Text
			tyreService := this.Window["tyreServiceEdit"].Text
			serviceOrder := this.Window["serviceOrderDropDown"].Value

			; Get additional context
			notes := this.Window["notesEdit"].Text

			; Block window while processing
			this.Window.Block()

			; Get laps database (no drivers needed for pre-race planning)
			lapsDB := LapsDatabase(simulator, car, track)

			; Get tyre data for all available compounds
			tyreEntries := []

			logMessage(kLogInfo, "Collecting tyre data for weather: " . weather)

			for ignore, compoundSpec in this.iCompounds {
				logMessage(kLogInfo, "Processing compound: " . compoundSpec)
				
				splitCompound(compoundSpec, &compoundName, &compoundColor)

				tempTyreEntries := lapsDB.getTyreEntries(weather, compoundName, compoundColor)
				for ignore, entry in tempTyreEntries
					tyreEntries.Push(entry)
			}

			if (tyreEntries.Length = 0) {
				OnMessage(0x44, translateOkButton)
				withBlockedWindows(MsgBox, translate("No laps data available for the selected conditions."), translate("Information"), 262192)
				OnMessage(0x44, translateOkButton, 0)
				this.Window.Unblock()
				return
			}

			; Build rules object
			rules := Map()
			rules["sessionType"] := sessionType
			rules["sessionLength"] := sessionLength . (sessionType = "Duration" ? " minutes" : " laps")
			rules["formationLap"] := formationLap ? "Yes" : "No"
			rules["postRaceLap"] := postRaceLap ? "Yes" : "No"

			if (pitstopRule = 2) ; Fixed
				rules["pitstopRule"] := requiredPitstops . " pitstops"
			else
				rules["pitstopRule"] := "Variable"

			if (pitstopWindow)
				rules["pitstopWindow"] := pitstopWindowFrom . "-" . pitstopWindowTo
			else
				rules["pitstopWindow"] := "No window"

			rules["refuelRequirement"] := (refuelRule = 1) ? "Required" : ((refuelRule = 2) ? "Optional" : "Not Allowed")
			rules["tyreChangeRequirement"] := (tyreChangeRule = 1) ? "Required" : ((tyreChangeRule = 2) ? "Optional" : "Not Allowed")

			if (validator > 1)
				rules["validator"] := ["FIA F1", "FIA F2", "FIA F3", "IMSA GT3", "GT World Challenge"][validator - 1]
			else
				rules["validator"] := "None"

			; Parse tyre sets
			if (tyreSets != "") {
				tyreSetList := StrSplit(tyreSets, ";")
				rules["tyreSets"] := []

				for ignore, tyreSetEntry in tyreSetList {
					parts := StrSplit(Trim(tyreSetEntry), "|")
					if (parts.Length >= 4) {
						rules["tyreSets"].Push(Map(
							"compound", Trim(parts[1]),
							"compoundColor", Trim(parts[2]),
							"count", Trim(parts[3]),
							"maxLaps", Trim(parts[4])
						))
					}
				}
			}

			; Build settings object
			settings := Map()
			settings["fuelCapacity"] := fuelCapacity . " liters"
			settings["safetyFuel"] := safetyFuel . " liters"
			settings["pitstopDelta"] := pitstopDelta . " seconds"

			fuelService := (fuelService = 1) ? "Simultaneous" : ((fuelService = 2) ? "Before Tyres" : "After Tyres")
			settings["pitstopFuelService"] := fuelService . " (" . refuelRate . " liters/sec)"
			settings["pitstopTyreService"] := tyreService . " seconds"
			settings["pitstopServiceOrder"] := (serviceOrder = 1) ? "Simultaneous" : ((serviceOrder = 2) ? "Tyre => Refuel" : "Refuel => Tyre")

			; Format data as JSON
			dataJSON := Map()
			dataJSON["simulator"] := simulator
			dataJSON["car"] := car
			dataJSON["track"] := track
			dataJSON["weather"] := weather
			dataJSON["airTemperature"] := airTemp
			dataJSON["trackTemperature"] := trackTemp
			dataJSON["rules"] := rules
			dataJSON["settings"] := settings
			dataJSON["lapsData"] := []

			; Filter tyre entries
			for ignore, entry in tyreEntries {
				filteredEntry := Map()
				for field, value in entry
					if (field != "Tyre.Laps"
					 && field != "Tyre.Laps.Front.Left" && field != "Tyre.Laps.Front.Right"
					 && field != "Tyre.Laps.Rear.Left" && field != "Tyre.Laps.Rear.Right"
					 && field != "Tyre.Pressure.Front.Left" && field != "Tyre.Pressure.Front.Right"
					 && field != "Tyre.Pressure.Rear.Left" && field != "Tyre.Pressure.Rear.Right"
					 && field != "Identifier" && field != "Synchronized")
						filteredEntry[field] := value

				dataJSON["lapsData"].Push(filteredEntry)
			}

			; Create enhanced prompt for LLM
			prompt := "You are a professional race strategist preparing a pre-race strategy for an upcoming race session.`n`n"
			prompt .= "TASK: Create a detailed race strategy including:`n"
			prompt .= "- Number and timing of pitstops`n"
			prompt .= "- Fuel amounts for each stint`n"
			prompt .= "- Tyre compound choices and when to change them`n"
			prompt .= "- Reasoning based on the historical lap data patterns`n`n"
			prompt .= "IMPORTANT CONTEXT:`n"
			prompt .= "- This is PRE-RACE planning, not real-time race management`n"
			prompt .= "- The historical laps data shows past performance at this track/car combination`n"
			prompt .= "- Use the data to identify optimal lap times, fuel consumption rates, and tyre degradation patterns`n"
			prompt .= "- Consider fuel weight reduction: As fuel burns off during the race, the car becomes lighter, resulting in faster lap times. Account for this when analyzing lap time progression and planning fuel loads.`n"
			prompt .= "- Consider the race rules and technical settings provided`n"

			if (notes && Trim(notes) != "") {
				prompt .= "- ADDITIONAL CONTEXT FROM USER: " . notes . "`n"
			}

			prompt .= "`nDATA PROVIDED (TOON format):`n" . this.printTOON(dataJSON)

			; Get LLM configuration
			service := getMultiMapValue(this.Configuration, "Agent Booster", "Race Strategist.Service", false)
			model := getMultiMapValue(this.Configuration, "Agent Booster", "Race Strategist.Model", false)

			if (!service || !model) {
				OnMessage(0x44, translateOkButton)
				withBlockedWindows(MsgBox, translate("LLM service not configured for Race Strategist. Please configure it in the Simulator Configuration."), translate("Error"), 262192)
				OnMessage(0x44, translateOkButton, 0)
				this.Window.Unblock()
				return
			}

			; Create manager
			manager := StrategyGenerator.SimpleLLMManager(this.Configuration)

			; Parse service configuration
			service := string2Values("|", service, 3)

			; Create LLM connector
			if (service[1] = "LLM Runtime")
				connector := LLMConnector.LLMRuntimeConnector(manager, model, getMultiMapValue(this.Configuration, "Agent Booster", "Race Strategist.GPULayers", 0))
			else {
				try {
					connector := LLMConnector.%StrReplace(service[1], A_Space, "")%Connector(manager, model)
					connector.Connect(service[2], service[3])
				}
				catch Any as exception {
					logError(exception)

					OnMessage(0x44, translateOkButton)
					withBlockedWindows(MsgBox, translate("Failed to create LLM connector. Please check your Race Strategist LLM configuration."), translate("Error"), 262192)
					OnMessage(0x44, translateOkButton, 0)
					this.Window.Unblock()
					return
				}
			}

			connector.MaxTokens := getMultiMapValue(this.Configuration, "Agent Booster", "Race Strategist.MaxTokens", 2048)
			connector.Temperature := 0.5

			; Call LLM
			response := connector.Ask(prompt, false, false)

			if response {
				this.showAIStrategyResponse(prompt, response)
			}
			else {
				OnMessage(0x44, translateOkButton)
				withBlockedWindows(MsgBox, translate("Failed to get response from LLM."), translate("Error"), 262192)
				OnMessage(0x44, translateOkButton, 0)
			}
		}
		catch Any as exception {
			logError(exception, true)

			OnMessage(0x44, translateOkButton)
			withBlockedWindows(MsgBox, translate("Error generating AI strategy: ") . exception.Message, translate("Error"), 262192)
			OnMessage(0x44, translateOkButton, 0)
		}
		finally {
			this.Window.Unblock()
		}
	}

	showAIStrategyResponse(prompt, response) {
		local responseGui, responseTab, promptEdit, responseEdit, x, y, width, height
		local mainScreenTop, mainScreenLeft, mainScreenRight, mainScreenBottom

		; Get screen dimensions
		MonitorGetWorkArea(, &mainScreenLeft, &mainScreenTop, &mainScreenRight, &mainScreenBottom)

		; Calculate window size
		width := Min(Round((mainScreenRight - mainScreenLeft) * 0.8), 1000)
		height := Min(Round((mainScreenBottom - mainScreenTop) * 0.8), 700)

		; Center on screen
		x := mainScreenLeft + Round((mainScreenRight - mainScreenLeft - width) / 2)
		y := mainScreenTop + Round((mainScreenBottom - mainScreenTop - height) / 2)

		; Create window
		responseGui := Window({Descriptor: "AI Strategy Response", Options: "Owner" . this.Window.Hwnd})

		responseGui.SetFont("s10", "Arial")
		responseGui.Add("Text", "x16 y16 w" . (width - 32), translate("AI Strategy Analysis:"))

		; Create tab control
		responseGui.SetFont("s9", "Arial")
		responseTab := responseGui.Add("Tab3", "x16 y40 w" . (width - 32) . " h" . (height - 100), collect([translate("Response"), translate("Prompt Sent")], translate))

		; Response tab
		responseTab.UseTab(1)
		responseGui.SetFont("s9", "Consolas")
		responseEdit := responseGui.Add("Edit", "x24 y72 w" . (width - 48) . " h" . (height - 140) . " ReadOnly VScroll +0x100000", response)

		; Prompt tab
		responseTab.UseTab(2)
		responseGui.SetFont("s9", "Consolas")
		promptEdit := responseGui.Add("Edit", "x24 y72 w" . (width - 48) . " h" . (height - 140) . " ReadOnly VScroll +0x100000", prompt)

		responseTab.UseTab()

		; Close button
		responseGui.SetFont("s10", "Arial")
		responseGui.Add("Button", "x" . Round((width - 100) / 2) . " y" . (height - 45) . " w100 h30 Default", translate("Close")).OnEvent("Click", (*) => responseGui.Destroy())

		responseGui.Show("x" . x . " y" . y . " w" . width . " h" . height)
	}

	show() {
		local window := this.Window
		local x, y

		x := "Center"
		y := "Center"

		window.Show("AutoSize x" . x . " y" . y)
	}

	close() {
		local window := this.Window

		window.Destroy()

		this.iClosed := true

		ExitApp(0)
	}

	printTOON(data, indent := "") {
		local result := ""
		local key, value, i, entry, fields, fieldList, row
		local fieldValue

		if (Type(data) = "Map") {
			for key, value in data {
				if (Type(value) = "Map") {
					; Nested object - use indentation
					result .= indent . key . ":`n"
					result .= this.printTOON(value, indent . "  ")
				}
				else if (Type(value) = "Array") {
					; Check if it's an array of maps (tabular data)
					if (value.Length > 0 && Type(value[1]) = "Map") {
						; Collect all unique fields from all entries
						fields := Map()
						for i, entry in value {
							for fieldKey, fieldValue in entry {
								if !fields.Has(fieldKey)
									fields[fieldKey] := true
							}
						}

						; Build field list
						fieldList := []
						for fieldKey, ignore in fields
							fieldList.Push(fieldKey)

						; Write array header with count and fields
						result .= indent . key . "[" . value.Length . "]{" . this.joinArray(fieldList, ",") . "}:`n"

						; Write data rows
						for i, entry in value {
							row := []
							for fieldKey in fieldList {
								if entry.Has(fieldKey)
									row.Push(this.formatTOONValue(entry[fieldKey]))
								else
									row.Push("")
							}
							result .= indent . "  " . this.joinArray(row, ",") . "`n"
						}
					}
					else if (value.Length > 0 && Type(value[1]) != "Map") {
						; Simple array
						result .= indent . key . "[" . value.Length . "]: " . this.joinArray(value, ",") . "`n"
					}
					else {
						; Empty array
						result .= indent . key . "[0]:`n"
					}
				}
				else {
					; Simple value
					result .= indent . key . ": " . this.formatTOONValue(value) . "`n"
				}
			}
		}

		return result
	}

	formatTOONValue(value) {
		local strValue := String(value)

		; If value contains comma, newline, or starts/ends with space, it needs quotes
		if (InStr(strValue, ",") || InStr(strValue, "`n") || RegExMatch(strValue, "^\s|\s$"))
			return '"' . StrReplace(StrReplace(strValue, '"', '\"'), "`n", "\n") . '"'

		return strValue
	}

	joinArray(arr, delimiter) {
		local result := ""
		local i, value

		for i, value in arr {
			if (i > 1)
				result .= delimiter
			result .= value
		}

		return result
	}
}


;;;-------------------------------------------------------------------------;;;
;;;                   Private Function Declaration Section                  ;;;
;;;-------------------------------------------------------------------------;;;

main() {
	global kIconsDirectory

	local icon := kIconsDirectory . "Workbench.ico"
	local aiStrategyGenerator

	TraySetIcon(icon, "1")
	A_IconTip := "AI Strategy Generator"

	try {
		aiStrategyGenerator := StrategyGenerator()

		aiStrategyGenerator.createGui()

		aiStrategyGenerator.show()

		startupApplication()

		loop
			Sleep(200)
	}
	catch Any as exception {
		logError(exception, true)

		OnMessage(0x44, translateOkButton)
		withBlockedWindows(MsgBox, substituteVariables(translate("Cannot start %application% due to an internal error..."), {application: "AI Strategy Generator"}), translate("Error"), 262160)
		OnMessage(0x44, translateOkButton, 0)

		ExitApp(1)
	}
}

exitApplication() {
	ExitApp(0)
}


;;;-------------------------------------------------------------------------;;;
;;;                         Initialization Section                         ;;;
;;;-------------------------------------------------------------------------;;;

main()
