#include "Core/BPGameMode.h"
#include "BushPilot.h"
#include "Player/BPPilot.h"

ABPGameMode::ABPGameMode()
{
	DefaultPawnClass = ABPPilot::StaticClass();
	UE_LOG(LogBushPilot, Log, TEXT("Bush Pilot game mode up"));
}
