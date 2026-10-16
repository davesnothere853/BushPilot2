using UnrealBuildTool;
using System.Collections.Generic;

public class BushPilotEditorTarget : TargetRules
{
	public BushPilotEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("BushPilot");
	}
}
