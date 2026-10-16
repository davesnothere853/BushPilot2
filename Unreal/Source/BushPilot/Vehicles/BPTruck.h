#pragma once
#include "CoreMinimal.h"
#include "Vehicles/BPVehicleBase.h"
#include "BPTruck.generated.h"

/** The test-bed pickup: an old 4x4 half-ton (placeholder shapes), 1,900 kg,
 *  a 5.0 litre engine through an automatic box, 4x4, our raycast tyres.
 *  W/S throttle and brake (S reverses once stopped), A/D steer, Space handbrake. */
UCLASS()
class BUSHPILOT_API ABPTruck : public ABPVehicleBase
{
	GENERATED_BODY()
public:
	ABPTruck();
	virtual void BeginPlay() override;
protected:
	virtual void Drive(float Dt, class APlayerController* PC) override;
	virtual FString Hud() const override;
	float Throttle = 0.f, SteerIn = 0.f;
	bool bReverse = false;
	int32 Gear = 1;
};
