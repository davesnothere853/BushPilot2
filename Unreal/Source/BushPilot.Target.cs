using UnrealBuildTool;
using System.Collections.Generic;

public class BushPilotTarget : TargetRules
{
	public BushPilotTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("BushPilot");
	}
}
