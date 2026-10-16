#pragma once
#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "BPGameMode.generated.h"

/** The game's rules: who spawns where, the clock, the season, the weather.
 *  (Grows as the systems arrive: jobs, money, co-op.) */
UCLASS()
class BUSHPILOT_API ABPGameMode : public AGameModeBase
{
	GENERATED_BODY()
public:
	ABPGameMode();
	/** Hours since midnight; the sun follows it. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "BushPilot|World")
	float TimeOfDay = 18.5f;
	/** 0 summer .. 1 deep winter. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "BushPilot|World")
	float Season = 0.2f;
};
