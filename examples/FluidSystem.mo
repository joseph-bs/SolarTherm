model FluidSystem
	import SI = Modelica.SIunits;
	import CN = Modelica.Constants;
	import CV = Modelica.SIunits.Conversions;
	import Modelica.Math.cos;
	//replaceable package MedRec = Modelica.Media.Water.ConstantPropertyLiquidWater;
	replaceable package MedRec = SolarTherm.Media.Sodium;

	inner Modelica.Fluid.System system(
		energyDynamics=Modelica.Fluid.Types.Dynamics.FixedInitial,
		//energyDynamics=Modelica.Fluid.Types.Dynamics.SteadyStateInitial,
		//energyDynamics=Modelica.Fluid.Types.Dynamics.SteadyState,
		//energyDynamics=Modelica.Fluid.Types.Dynamics.DynamicFreeInitial,
		allowFlowReversal=false
		);
	// Can provide details of modelling accuracy, assumptions and initialisation

	// When heat fluid is removed from cold tank (none entering), the temperature
	// creeps up.  It seems link this might be a numerical error as the specific
	// internal energy is calculated from the total internal energy of the tank.
	// The latter can be a huge numerical value.
	// The change in total internal energy is calculated from the mass flows
	// in and out of the tank.  If there is some mismatch between the total mass
	// and the flow mass then a sizeable temperature creep (5deg) can occur...

	parameter String weaFile = "resources/weatherfile1.motab";

	parameter SI.Power P_rated = 20e3 "Rating of power block";
	parameter SI.Efficiency eff_adj = 0.50 "Adjustment factor for power block efficiency";
	parameter SI.Efficiency eff_est = 0.20 "Estimate of overall power block efficiency";

	parameter SI.Area A_con = 500 "Concentrator area";

	parameter SI.Area A_rec = 1 "Receiver area";
	parameter Real em_steel = 0.85 "Emissivity of reciever";
	parameter SI.CoefficientOfHeatTransfer h_th_rec = 10 "Receiver heat tran coeff";

	parameter SI.Time t_storage = CV.from_hour(5) "Storage capacity as time at rated output";
	parameter SI.Area A_tnk = 10 "Cross-sectional area of tanks";
	parameter SI.Length L_tnk = (1/eff_est)*P_rated*t_storage/ // only works with PartialSimpleMedium
		(MedRec.cp_const*MedRec.d_const*A_tnk*(T_hot_set - T_cold_set)) "Height of tanks";
	parameter MedRec.Temperature T_cold_set = CV.from_degC(290) "Target cold tank T";
	parameter MedRec.Temperature T_hot_set = CV.from_degC(565) "Target hot tank T";
	parameter MedRec.Temperature T_cold_start = CV.from_degC(290) "Cold tank starting T";
	parameter MedRec.Temperature T_hot_start = CV.from_degC(565) "Hot tank starting T";
	parameter Real split_cold = 0.8 "Starting fluid fraction in cold tank";

	parameter SI.RadiantPower R_go = 200*A_con "Receiver radiant power for running";
	parameter SI.MassFlowRate m_flow_fac = 1.2 "Mass flow factor for receiver";
	parameter SI.MassFlowRate m_flow_pblk = (1/eff_est)*P_rated/
		(MedRec.cp_const*(T_hot_set - T_cold_set)) "Mass flow rate for power block";
	parameter SI.Length L_up_warn = 0.85*L_tnk;
	parameter SI.Length L_up_stop = 0.95*L_tnk;

	SolarTherm.Utilities.Weather.WeatherSource wea(weaFile=weaFile);

	SolarTherm.Optics.IdealInc con(A_con=A_con, A_foc=A_rec);

	SolarTherm.Receivers.Plate rec(
		redeclare package Medium=MedRec,
		A=A_rec, em=em_steel, h_th=h_th_rec);

	SolarTherm.Pumps.IdealPump pmp_rec(
		redeclare package Medium=MedRec,
		cont_m_flow=true,
		use_input=true
		);

	SolarTherm.Pumps.IdealPump pmp_exc(
		redeclare package Medium=MedRec,
		cont_m_flow=true,
		use_input=true
		);

	//parameter Modelica.Fluid.Vessels.BaseClasses.VesselPortsData port_dat(
	//	diameter=0.1,
	//	height=0.0
	//	);
	Modelica.Fluid.Vessels.OpenTank ctnk(
		redeclare package Medium=MedRec,
		height=L_tnk,
		crossArea=A_tnk,
		level_start=L_tnk*split_cold,
		nPorts=2,
		use_T_start=true,
		T_start=T_cold_start,
		use_HeatTransfer=false,
		use_portsData=false
		//portsData={port_dat, port_dat}
		);
	Modelica.Fluid.Vessels.OpenTank htnk(
		redeclare package Medium=MedRec,
		height=L_tnk,
		crossArea=A_tnk,
		level_start=L_tnk*(1 - split_cold),
		nPorts=2,
		use_T_start=true,
		T_start=T_hot_start,
		use_HeatTransfer=false,
		use_portsData=false
		//portsData={port_dat, port_dat}
		);

	SolarTherm.HeatExchangers.Extractor ext(
		redeclare package Medium=MedRec,
		eff = 0.9,
		use_input=false,
		T_fixed=T_cold_set
		);

	SolarTherm.PowerBlocks.HeatGen pblk(
		P_rated=P_rated,
		eff_adj=eff_adj
		);

	SolarTherm.Control.Trigger hf_trig(
		low=L_up_warn,
		up=L_up_stop);
	SolarTherm.Control.Trigger cf_trig(
		low=L_up_warn,
		up=L_up_stop);

	Boolean radiance_good "Adequate radiant power on receiver";
	Boolean fill_htnk "Hot tank can be filled";
	Boolean fill_ctnk "Cold tank can be filled";
equation
	connect(wea.wbus, con.wbus);
	connect(wea.wbus, rec.wbus);
	connect(wea.wbus, pblk.wbus);
	connect(con.R_foc, rec.R);
	connect(ctnk.ports[1], pmp_rec.port_a);
	connect(pmp_rec.port_b, rec.port_a);
	connect(rec.port_b, htnk.ports[1]);

	connect(htnk.ports[2], pmp_exc.port_a);
	connect(pmp_exc.port_b, ext.port_a);
	connect(ext.port_b, ctnk.ports[2]);

	connect(ext.Q_flow, pblk.Q_flow);
	connect(ext.T, pblk.T);

	connect(hf_trig.x, htnk.level);
	connect(cf_trig.x, ctnk.level);

	radiance_good = rec.R >= R_go;

	fill_htnk = not hf_trig.y;
	fill_ctnk = not cf_trig.y;

	rec.door_open = radiance_good and fill_htnk;
	pmp_rec.m_flow_set = if radiance_good and fill_htnk then m_flow_fac*rec.R/(A_con*1000) else 0;
	pmp_exc.m_flow_set = if fill_ctnk then m_flow_pblk else 0;

	con.track = true;
end FluidSystem;
