#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "BPPilot.generated.h"

class UCameraComponent;

/** The pilot on foot (test bed): 1.8 m, first person, WASD + mouse, Shift runs,
 *  Space jumps, F gets into the nearest vehicle (within 5 m of its door). */
UCLASS()
class BUSHPILOT_API ABPPilot : public ACharacter
{
	GENERATED_BODY()
public:
	ABPPilot();
	virtual void Tick(float Dt) override;
	UPROPERTY(VisibleAnywhere, Category = "Pilot") UCameraComponent* Eyes;
};
