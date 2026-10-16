#pragma once
#include "CoreMinimal.h"
#include "Vehicles/BPVehicleBase.h"
#include "BPPlane.generated.h"

/** One lifting surface of the flight model (body frame, cm). */
struct FBPSurface
{
	FVector Pos;          // centre of pressure
	FVector Normal;       // lift side
	FVector Span;         // along the span
	float Area;           // cm^2
	float Cla;            // lift slope per radian
	float Cd0;
	float Control = 0.f;  // deflection added to the angle of attack (radians)
	float StallDeg = 15.f;
};

/** The test-bed bush plane: a high-wing taildragger (Cub-sized, placeholder
 *  shapes), 800 kg, 180 hp. Our own flight model: each surface (wing halves,
 *  tailplane, fin) gets lift and drag from the air it meets, so it stalls,
 *  drops a wing, weathervanes and flies the way the shape says.
 *  Shift/Ctrl throttle, W/S pitch, A/D roll, Q/E rudder, B brakes, G flaps. */
UCLASS()
class BUSHPILOT_API ABPPlane : public ABPVehicleBase
{
	GENERATED_BODY()
public:
	ABPPlane();
protected:
	virtual void Drive(float Dt, class APlayerController* PC) override;
	virtual FString Hud() const override;
	TArray<FBPSurface> Surf;
	UStaticMeshComponent* Prop = nullptr;
	float Throttle = 0.f, Pitch = 0.f, Roll = 0.f, Yaw = 0.f, Flaps = 0.f, PropDeg = 0.f;
	float Aoa = 0.f, Ias = 0.f;
};
