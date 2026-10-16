#include "World/BPMudComponent.h"
#include "BushPilot.h"

UBPMudComponent::UBPMudComponent()
{
	PrimaryComponentTick.bCanEverTick = false;
}

void UBPMudComponent::BeginPlay()
{
	Super::BeginPlay();
	NX = FMath::Max(1, FMath::CeilToInt(FieldSize.X / CellSize));
	NY = FMath::Max(1, FMath::CeilToInt(FieldSize.Y / CellSize));
	Depth.Init(0.f, NX * NY);
	Rut.Init(0.f, NX * NY);
	UE_LOG(LogBushPilot, Log, TEXT("Mud field %d x %d cells"), NX, NY);
}

bool UBPMudComponent::Cell(const FVector& P, int32& I, int32& J) const
{
	const float X = P.X / 100.f - FieldOrigin.X;     // cm -> m
	const float Y = P.Y / 100.f - FieldOrigin.Y;
	I = FMath::FloorToInt(X / CellSize);
	J = FMath::FloorToInt(Y / CellSize);
	return I >= 0 && J >= 0 && I < NX && J < NY;
}

void UBPMudComponent::Query(const FVector& P, float PressureKPa, float& OutSinkCm, float& OutDrag, float& OutGrip) const
{
	OutSinkCm = 0.f; OutDrag = 0.015f; OutGrip = 1.f;
	int32 I, J;
	if (!Cell(P, I, J) || Depth.Num() == 0) return;
	const int32 K = J * NX + I;
	const float Mud = Depth[K] + Rut[K] * 0.5f;           // soft stuff under the tyre (cm)
	// sinkage grows with pressure and wetness, limited by how much mud there is
	OutSinkCm = FMath::Min(Mud, Mud * FMath::Clamp(PressureKPa / 250.f, 0.1f, 1.5f) * (0.4f + 0.6f * Wetness));
	// bulldozing drag rises with sinkage; grip falls when it's wet and greasy
	OutDrag = 0.015f + 0.012f * OutSinkCm;
	OutGrip = FMath::Lerp(1.f, 0.45f, Wetness * FMath::Clamp(Mud / 20.f, 0.f, 1.f));
}

void UBPMudComponent::Churn(const FVector& P, float WidthM, float SinkCm, float SlipRatio)
{
	int32 I, J;
	if (!Cell(P, I, J) || Rut.Num() == 0) return;
	const int32 R = FMath::Max(0, FMath::RoundToInt(WidthM * 0.5f / CellSize));
	const float Dig = SinkCm * 0.02f * (1.f + 4.f * FMath::Clamp(FMath::Abs(SlipRatio), 0.f, 1.f));
	for (int32 dj = -R; dj <= R; ++dj)
		for (int32 di = -R; di <= R; ++di)
		{
			const int32 ii = I + di, jj = J + dj;
			if (ii < 0 || jj < 0 || ii >= NX || jj >= NY) continue;
			float& Cur = Rut[jj * NX + ii];
			Cur = FMath::Min(Cur + Dig, 60.f);
		}
}

float UBPMudComponent::RutDepth(const FVector& P) const
{
	int32 I, J;
	return (Cell(P, I, J) && Rut.Num() > 0) ? Rut[J * NX + I] : 0.f;
}
