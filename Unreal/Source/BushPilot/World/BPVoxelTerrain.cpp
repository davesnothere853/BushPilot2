#include "World/BPVoxelTerrain.h"
#include "BushPilot.h"
#include "ProceduralMeshComponent.h"
#include "Materials/MaterialInterface.h"
#include "Engine/World.h"
#include "Engine/Engine.h"
#include "Engine/StaticMesh.h"
#include "Engine/StaticMeshActor.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/Pawn.h"
#include "DrawDebugHelpers.h"
#include "Async/ParallelFor.h"
#include "InputCoreTypes.h"

namespace
{
	inline float SmoothStep01(float A, float B, float X)
	{
		const float T = FMath::Clamp((X - A) / (B - A), 0.f, 1.f);
		return T * T * (3.f - 2.f * T);
	}
	inline int32 FloorDiv(int32 A, int32 B) { return (A >= 0) ? (A / B) : -((-A + B - 1) / B); }

	/** Repose: the steepest slope (rise over run) the soil holds when dry. */
	inline float ReposeTan(EBPSoil S)
	{
		switch (S)
		{
		case EBPSoil::Sand: return 0.62f;       // ~32 deg
		case EBPSoil::Loose: return 0.72f;      // ~36 deg
		case EBPSoil::Gravel: return 0.80f;     // ~39 deg
		case EBPSoil::PayGravel: return 0.85f;
		case EBPSoil::Topsoil: return 1.6f;     // roots hold a steep cut for a while
		case EBPSoil::Clay: return 3.0f;        // stands near vertical
		default: return 100.f;                  // rock
		}
	}

	inline FLinearColor SoilColor(uint8 S)
	{
		// R gravel, G clay, B rock, A topsoil; all zero = plain brown dirt / sand
		switch ((EBPSoil)S)
		{
		case EBPSoil::Topsoil: return FLinearColor(0, 0, 0, 1);
		case EBPSoil::Sand: return FLinearColor(0, 0, 0, 0);
		case EBPSoil::Gravel: return FLinearColor(1, 0, 0, 0);
		case EBPSoil::Clay: return FLinearColor(0, 1, 0, 0);
		case EBPSoil::PayGravel: return FLinearColor(0.8f, 0.3f, 0, 0);
		case EBPSoil::Weathered: return FLinearColor(0.4f, 0.2f, 0.6f, 0);
		case EBPSoil::Bedrock: return FLinearColor(0, 0, 1, 0);
		case EBPSoil::Loose: return FLinearColor(0.35f, 0.25f, 0, 0.1f);
		default: return FLinearColor(0, 0, 0, 0);
		}
	}
}

ABPVoxelTerrain::ABPVoxelTerrain()
{
	PrimaryActorTick.bCanEverTick = true;
	Root = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	RootComponent = Root;
}

float ABPVoxelTerrain::Hardness(EBPSoil S)
{
	switch (S)
	{
	case EBPSoil::Loose: return 1.0f;
	case EBPSoil::Sand: return 0.9f;
	case EBPSoil::Topsoil: return 0.6f;   // roots
	case EBPSoil::Gravel: return 0.6f;
	case EBPSoil::PayGravel: return 0.5f;
	case EBPSoil::Clay: return 0.35f;
	case EBPSoil::Weathered: return 0.12f;
	case EBPSoil::Bedrock: return 0.015f;
	default: return 0.f;
	}
}

float ABPVoxelTerrain::Mobility(EBPSoil S)
{
	switch (S)
	{
	case EBPSoil::Loose: return 0.55f;
	case EBPSoil::Sand: return 0.6f;
	case EBPSoil::Gravel: return 0.4f;
	case EBPSoil::PayGravel: return 0.3f;
	case EBPSoil::Topsoil: return 0.12f;
	case EBPSoil::Clay: return 0.03f;
	default: return 0.f;
	}
}

bool ABPVoxelTerrain::Runs(EBPSoil S)
{
	return S == EBPSoil::Sand || S == EBPSoil::Loose;
}

// ---------------------------------------------------------------- the ground

float ABPVoxelTerrain::GroundHeight(float Xm, float Ym) const
{
	float H = 1.2f * FMath::PerlinNoise2D(FVector2D(Xm, Ym) / 37.f)
		+ 0.45f * FMath::PerlinNoise2D(FVector2D(Xm + 31.f, Ym) / 11.f)
		+ 0.10f * FMath::PerlinNoise2D(FVector2D(Xm, Ym + 17.f) / 3.1f);
	// a 7 m bank along one side of the test ground: dig into it, cut a face, drive a drift
	const float Edge = 6.f + 3.f * FMath::PerlinNoise2D(FVector2D(Xm / 23.f, 0.5f));
	H += 7.f * SmoothStep01(Edge - 5.f, Edge + 5.f, Ym);
	return H;
}

void ABPVoxelTerrain::GroundColumn(int32 PX, int32 PY, float& OutH, float& OutCos) const
{
	// height and how steep it is there: the fill ramps across the surface measured
	// square to the slope, so steep banks come out smooth instead of in steps
	const float S = VoxelSize / 100.f;
	const float X = PX * S, Y = PY * S, E = 0.25f;
	OutH = GroundHeight(X, Y);
	const float Gx = (GroundHeight(X + E, Y) - GroundHeight(X - E, Y)) / (2.f * E);
	const float Gy = (GroundHeight(X, Y + E) - GroundHeight(X, Y - E)) / (2.f * E);
	OutCos = 1.f / FMath::Sqrt(1.f + Gx * Gx + Gy * Gy);
}

float ABPVoxelTerrain::FillFromColumn(float H, float Cos, int32 PZ) const
{
	const float S = VoxelSize / 100.f;
	return FMath::Clamp(0.5f + (H - PZ * S) * Cos / S, 0.f, 1.f);
}

float ABPVoxelTerrain::GenFill(const FIntVector& P) const
{
	float H, Cos;
	GroundColumn(P.X, P.Y, H, Cos);
	return FillFromColumn(H, Cos, P.Z);
}

uint8 ABPVoxelTerrain::GenSoil(const FIntVector& P) const
{
	const float S = VoxelSize / 100.f;
	const float X = P.X * S, Y = P.Y * S, Z = P.Z * S;
	const float H = GroundHeight(X, Y);
	const float Depth = H - Z;
	const FVector Q(X, Y, Z);
	const float Wob = FMath::PerlinNoise3D(Q / 6.f);
	if (Depth < 0.30f + 0.15f * Wob) return (uint8)EBPSoil::Topsoil;
	// the bedrock surface: undulating, ~6 m down under the flat, deeper under the bank
	const float Rock = H - 5.8f - 1.4f * FMath::PerlinNoise2D(FVector2D(X, Y) / 14.f) - 0.5f * SmoothStep01(4.f, 14.f, Y) * 7.f;
	if (Z < Rock - 1.2f) return (uint8)EBPSoil::Bedrock;
	if (Z < Rock) return (uint8)EBPSoil::Weathered;
	if (Z < Rock + 0.9f + 0.3f * Wob) return (uint8)EBPSoil::PayGravel;
	// clay band, then sand and gravel lenses (old river beds), cross-bedded
	const float ClayTop = Rock + 2.2f + 0.8f * FMath::PerlinNoise2D(FVector2D(X, Y) / 9.f);
	if (Z < ClayTop) return (uint8)EBPSoil::Clay;
	const float Lens = FMath::PerlinNoise3D(FVector(X / 5.f, Y / 5.f, Z / 1.3f + X * 0.05f));
	return (uint8)(Lens > 0.08f ? EBPSoil::Sand : EBPSoil::Gravel);
}

// ---------------------------------------------------------------- access

FIntVector ABPVoxelTerrain::ChunkOf(const FIntVector& P) const
{
	return FIntVector(FloorDiv(P.X, ChunkCells), FloorDiv(P.Y, ChunkCells), FloorDiv(P.Z, ChunkCells));
}

FBPVoxelChunk* ABPVoxelTerrain::FindChunk(const FIntVector& C) const
{
	const TUniquePtr<FBPVoxelChunk>* Found = Chunks.Find(C);
	return Found ? Found->Get() : nullptr;
}

FBPVoxelChunk* ABPVoxelTerrain::GetOrCreateChunk(const FIntVector& C)
{
	if (!InArea(C))
	{
		return nullptr;
	}
	if (FBPVoxelChunk* Existing = FindChunk(C))
	{
		return Existing;
	}
	TUniquePtr<FBPVoxelChunk> New = MakeUnique<FBPVoxelChunk>();
	New->Coord = C;
	UProceduralMeshComponent* Mesh = NewObject<UProceduralMeshComponent>(this);
	Mesh->bUseAsyncCooking = true;
	Mesh->SetupAttachment(Root);
	Mesh->SetCollisionProfileName(TEXT("BlockAll"));
	Mesh->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
	Mesh->RegisterComponent();
	if (Material)
	{
		Mesh->SetMaterial(0, Material);
	}
	MeshComponents.Add(Mesh);
	New->Mesh = Mesh;
	FBPVoxelChunk* Raw = New.Get();
	Chunks.Add(C, MoveTemp(New));
	return Raw;
}

void ABPVoxelTerrain::EnsureData(FBPVoxelChunk& Ch) const
{
	if (Ch.HasData())
	{
		return;
	}
	const int32 N = ChunkCells;
	Ch.F.SetNumUninitialized(N * N * N);
	Ch.M.SetNumUninitialized(N * N * N);
	const FIntVector Base = Ch.Coord * N;
	for (int32 Y = 0; Y < N; ++Y)
		for (int32 X = 0; X < N; ++X)
		{
			float H, Cos;
			GroundColumn(Base.X + X, Base.Y + Y, H, Cos);
			for (int32 Z = 0; Z < N; ++Z)
			{
				const FIntVector P = Base + FIntVector(X, Y, Z);
				const int32 I = Index(FIntVector(X, Y, Z));
				Ch.F[I] = FillFromColumn(H, Cos, P.Z);
				Ch.M[I] = GenSoil(P);
			}
		}
}

float ABPVoxelTerrain::Fill(const FIntVector& P) const
{
	const FIntVector C = ChunkOf(P);
	if (const FBPVoxelChunk* Ch = FindChunk(C))
	{
		if (Ch->HasData())
		{
			return Ch->F[Index(LocalOf(P, C))];
		}
	}
	return GenFill(P);
}

uint8 ABPVoxelTerrain::Soil(const FIntVector& P) const
{
	const FIntVector C = ChunkOf(P);
	if (const FBPVoxelChunk* Ch = FindChunk(C))
	{
		if (Ch->HasData())
		{
			return Ch->M[Index(LocalOf(P, C))];
		}
	}
	return GenSoil(P);
}

bool ABPVoxelTerrain::PointRef(const FIntVector& P, float*& OutF, uint8*& OutM)
{
	const FIntVector C = ChunkOf(P);
	FBPVoxelChunk* Ch = GetOrCreateChunk(C);
	if (!Ch)
	{
		return false;
	}
	EnsureData(*Ch);
	const int32 I = Index(LocalOf(P, C));
	OutF = &Ch->F[I];
	OutM = &Ch->M[I];
	return true;
}

void ABPVoxelTerrain::Touch(const FIntVector& P, float ActiveSeconds)
{
	const FIntVector C = ChunkOf(P);
	const FIntVector L = LocalOf(P, C);
	const int32 N = ChunkCells;
	// this chunk, and every neighbour whose mesh reads this point
	for (int32 DZ = -1; DZ <= 1; ++DZ)
		for (int32 DY = -1; DY <= 1; ++DY)
			for (int32 DX = -1; DX <= 1; ++DX)
			{
				const FIntVector D(DX, DY, DZ);
				bool bNeeded = true;
				for (int32 A = 0; A < 3; ++A)
				{
					const int32 Dv = D[A];
					const int32 Lv = L[A];
					if ((Dv < 0 && Lv > 1) || (Dv > 0 && Lv < N - 2))
					{
						bNeeded = false;
					}
				}
				if (!bNeeded)
				{
					continue;
				}
				// chunks below/behind own the faces that meet this point: make them if missing
				FBPVoxelChunk* Ch = (DX <= 0 && DY <= 0 && DZ <= 0) ? GetOrCreateChunk(C + D) : FindChunk(C + D);
				if (Ch)
				{
					Ch->bDirty = true;
					if (D == FIntVector::ZeroValue)
					{
						Ch->Active = FMath::Max(Ch->Active, ActiveSeconds);
					}
				}
			}
}

EBPSoil ABPVoxelTerrain::SoilAt(FVector WorldPoint) const
{
	const FVector L = (WorldPoint - GetActorLocation()) / VoxelSize;
	return (EBPSoil)Soil(FIntVector(FMath::RoundToInt(L.X), FMath::RoundToInt(L.Y), FMath::RoundToInt(L.Z)));
}

// ---------------------------------------------------------------- digging

float ABPVoxelTerrain::Brush(FVector WorldCenter, float RadiusM, float Amount)
{
	const FVector Cv = (WorldCenter - GetActorLocation()) / VoxelSize;
	const float Rv = RadiusM * 100.f / VoxelSize;
	const int32 R = FMath::CeilToInt(Rv);
	const FIntVector C0(FMath::RoundToInt(Cv.X), FMath::RoundToInt(Cv.Y), FMath::RoundToInt(Cv.Z));
	const float CellM3 = FMath::Pow(VoxelSize / 100.f, 3.f);
	float Moved = 0.f;
	for (int32 Z = -R; Z <= R; ++Z)
		for (int32 Y = -R; Y <= R; ++Y)
			for (int32 X = -R; X <= R; ++X)
			{
				const FIntVector P = C0 + FIntVector(X, Y, Z);
				const float Dist = FVector::Dist(FVector(P), Cv);
				const float W = 1.f - SmoothStep01(Rv * 0.45f, Rv, Dist);
				if (W <= 0.f)
				{
					continue;
				}
				float* F;
				uint8* M;
				if (!PointRef(P, F, M))
				{
					continue;
				}
				if (Amount > 0.f)
				{
					const float D = FMath::Min(*F, Amount * W * Hardness((EBPSoil)*M));
					if (D <= 0.f)
					{
						continue;
					}
					*F -= D;
					Moved += D;
				}
				else
				{
					const float D = FMath::Min(1.f - *F, -Amount * W);
					if (D <= 0.f)
					{
						continue;
					}
					if (*F < 0.5f)
					{
						*M = (uint8)EBPSoil::Loose;
					}
					*F += D;
					Moved += D;
				}
				Touch(P, 3.f);
			}
	return Moved * CellM3;
}

// ---------------------------------------------------------------- soil behaviour

bool ABPVoxelTerrain::MoveSoil(const FIntVector& From, const FIntVector& To, float Amount)
{
	float *FA, *FB;
	uint8 *MA, *MB;
	if (Amount <= 1e-4f || !PointRef(From, FA, MA) || !PointRef(To, FB, MB))
	{
		return false;
	}
	Amount = FMath::Min3(Amount, *FA, 1.f - *FB);
	if (Amount <= 1e-4f)
	{
		return false;
	}
	if (*FB < 0.5f)
	{
		// moved dirt is disturbed dirt: it becomes loose (except sand stays sand)
		*MB = (*MA == (uint8)EBPSoil::Sand) ? *MA : (uint8)EBPSoil::Loose;
	}
	*FA -= Amount;
	*FB += Amount;
	Touch(From, 1.5f);
	Touch(To, 1.5f);
	return true;
}

void ABPVoxelTerrain::SimStep()
{
	++SimFrame;
	TArray<FBPVoxelChunk*> Active;
	for (auto& Pair : Chunks)
	{
		FBPVoxelChunk* Ch = Pair.Value.Get();
		if (Ch->Active > 0.f && Ch->HasData())
		{
			Active.Add(Ch);
		}
	}
	// bottom-up so a falling column moves as one
	Active.Sort([](const FBPVoxelChunk& A, const FBPVoxelChunk& B) { return A.Coord.Z < B.Coord.Z; });
	const int32 N = ChunkCells;
	static const FIntVector Dirs[8] = {
		FIntVector(1, 0, 0), FIntVector(0, 1, 0), FIntVector(-1, 0, 0), FIntVector(0, -1, 0),
		FIntVector(1, 1, 0), FIntVector(-1, 1, 0), FIntVector(-1, -1, 0), FIntVector(1, -1, 0)};
	const float Diag = 1.41421356f;

	for (FBPVoxelChunk* Ch : Active)
	{
		const FIntVector Base = Ch->Coord * N;
		auto LocalF = [&](const FIntVector& L) -> float
		{
			if (L.X >= 0 && L.Y >= 0 && L.Z >= 0 && L.X < N && L.Y < N && L.Z < N)
			{
				return Ch->F[Index(L)];
			}
			return Fill(Base + L);
		};
		for (int32 Z = 0; Z < N; ++Z)
			for (int32 Y = 0; Y < N; ++Y)
				for (int32 Xi = 0; Xi < N; ++Xi)
				{
					const int32 X = (SimFrame & 1) ? Xi : (N - 1 - Xi);
					const FIntVector L(X, Y, Z);
					const int32 I = Index(L);
					const float Fp = Ch->F[I];
					if (Fp <= 1e-3f)
					{
						continue;
					}
					const float Fu = LocalF(L + FIntVector(0, 0, 1));
					if (Fp >= 0.999f && Fu >= 0.999f && LocalF(L + FIntVector(1, 0, 0)) >= 0.999f && LocalF(L - FIntVector(1, 0, 0)) >= 0.999f
						&& LocalF(L + FIntVector(0, 1, 0)) >= 0.999f && LocalF(L - FIntVector(0, 1, 0)) >= 0.999f)
					{
						continue;   // buried
					}
					const EBPSoil S = (EBPSoil)Ch->M[I];
					const float Mob = Mobility(S);
					if (Mob <= 0.f)
					{
						continue;
					}
					const FIntVector P = Base + L;
					// 1) falling: nothing under it
					const float Fd = LocalF(L - FIntVector(0, 0, 1));
					if (Fd < 0.999f)
					{
						// loose stuff drops straight away; native soil drops once it is undercut
						const bool bUndercut = Fd < 0.5f;
						float Rate = (S == EBPSoil::Loose || S == EBPSoil::Sand) ? 1.f : (bUndercut ? Mob : 0.f);
						if (Rate > 0.f && S != EBPSoil::Loose && S != EBPSoil::Sand)
						{
							// cohesive ground arches over a narrow opening: it only drops when the span
							// under it is wider than it can hold (clay ~3 m, gravel ~1.5 m, turf ~1 m)
							const int32 Span = (S == EBPSoil::Clay) ? 6 : (S == EBPSoil::Topsoil ? 2 : 3);
							bool bHeld = false;
							for (int32 Ax = 0; Ax < 2 && !bHeld; ++Ax)
							{
								const FIntVector Side(Ax == 0 ? 1 : 0, Ax == 1 ? 1 : 0, 0);
								bool bL = false, bR = false;
								for (int32 K = 1; K <= Span; ++K)
								{
									bL |= LocalF(L - Side * K - FIntVector(0, 0, 1)) >= 0.5f;
									bR |= LocalF(L + Side * K - FIntVector(0, 0, 1)) >= 0.5f;
								}
								bHeld = bL && bR;
							}
							if (bHeld)
							{
								Rate = 0.f;
							}
						}
						if (Rate > 0.f && MoveSoil(P, P - FIntVector(0, 0, 1), (1.f - Fd) * Rate))
						{
							continue;
						}
						if (Fd < 0.5f)
						{
							continue;
						}
					}
					// 2) slope failure. Any point with open air beside it is part of a face. Compare
					//    the height of soil on this side (this point and everything stacked on it)
					//    with the ground surface on the open side: steeper than the soil holds and
					//    the face lets go - the point slides out and falls, the soil above it is
					//    undercut and follows. Cuts in sand run back to a ~32 deg slope; gravel
					//    a bit steeper; clay stands; turf hangs over and then breaks off.
					const float Tan = ReposeTan(S);
					const int32 Start = (SimFrame * 3 + X + Y * 5) & 7;
					float Hp = -1.f;           // computed on demand
					for (int32 K = 0; K < 8; ++K)
					{
						const int32 Di = (Start + K) & 7;
						const FIntVector D = Dirs[Di];
						const float Run = (Di & 4) ? Diag : 1.f;
						const float Fs = LocalF(L + D);
						if (Fs >= 0.5f)
						{
							continue;          // soil beside it on this side
						}
						if (Hp < 0.f)
						{
							Hp = Fp;
							for (int32 U = 1; U <= 16; ++U)
							{
								const float Fa = LocalF(L + FIntVector(0, 0, U));
								if (Fa <= 0.01f)
								{
									break;
								}
								Hp += Fa;
							}
						}
						// the ground surface on the open side (cells, relative to P.z)
						float Hn = -16.f;
						if (Fs > 0.01f)
						{
							Hn = Fs;
						}
						else
						{
							for (int32 Dn = 1; Dn <= 16; ++Dn)
							{
								const float Fb = LocalF(L + D - FIntVector(0, 0, Dn));
								if (Fb > 0.01f)
								{
									Hn = Fb - Dn;
									break;
								}
							}
						}
						const float Slope = (Hp - Hn) / Run;
						if (Slope <= Tan)
						{
							continue;
						}
						// how fast it goes: dry loose stuff pours, firm soil calves off in pieces
						const float Amt = FMath::Min(Fp, Mob * 0.35f * (Slope - Tan));
						if (MoveSoil(P, P + D, Amt))
						{
							break;
						}
					}
				}
	}
}

// ---------------------------------------------------------------- meshing (surface nets)

void ABPVoxelTerrain::BuildMesh(const FIntVector& Cc, FBPChunkMeshData& Out) const
{
	Out.Coord = Cc;
	const int32 N = ChunkCells;
	const int32 S = N + 3;                        // points -1 .. N+1
	const FIntVector Base = Cc * N;
	TArray<float> Fc;
	TArray<uint8> Mc;
	Fc.SetNumUninitialized(S * S * S);
	Mc.SetNumUninitialized(S * S * S);
	auto CI = [S](int32 X, int32 Y, int32 Z) { return (X + 1) + S * ((Y + 1) + S * (Z + 1)); };

	// the untouched ground's height per column, once
	TArray<float> ColH, ColCos;
	ColH.SetNumUninitialized(S * S);
	ColCos.SetNumUninitialized(S * S);
	for (int32 Y = -1; Y <= N + 1; ++Y)
		for (int32 X = -1; X <= N + 1; ++X)
		{
			GroundColumn(Base.X + X, Base.Y + Y, ColH[(X + 1) + S * (Y + 1)], ColCos[(X + 1) + S * (Y + 1)]);
		}
	// fill the cache: chunk data where it exists, the generator elsewhere
	bool bAnyAir = false, bAnySolid = false;
	for (int32 Z = -1; Z <= N + 1; ++Z)
		for (int32 Y = -1; Y <= N + 1; ++Y)
			for (int32 X = -1; X <= N + 1; ++X)
			{
				const FIntVector P = Base + FIntVector(X, Y, Z);
				const FIntVector C = ChunkOf(P);
				const FBPVoxelChunk* Ch = FindChunk(C);
				float Fv;
				uint8 Mv;
				if (Ch && Ch->HasData())
				{
					const int32 I = Index(LocalOf(P, C));
					Fv = Ch->F[I];
					Mv = Ch->M[I];
				}
				else
				{
					Fv = FillFromColumn(ColH[(X + 1) + S * (Y + 1)], ColCos[(X + 1) + S * (Y + 1)], P.Z);
					Mv = 0;   // looked up below only where needed
				}
				Fc[CI(X, Y, Z)] = Fv;
				Mc[CI(X, Y, Z)] = Mv;
				bAnyAir |= Fv < 0.5f;
				bAnySolid |= Fv >= 0.5f;
			}
	if (!bAnyAir || !bAnySolid)
	{
		return;
	}

	// one vertex per cell the surface passes through (cells -1 .. N-1)
	const int32 VS = N + 1;
	TArray<int32> VIdx;
	VIdx.Init(INDEX_NONE, VS * VS * VS);
	auto VI = [VS](int32 X, int32 Y, int32 Z) { return (X + 1) + VS * ((Y + 1) + VS * (Z + 1)); };
	const float Vs = VoxelSize;
	static const int32 Edges[12][2] = {{0, 1}, {2, 3}, {4, 5}, {6, 7}, {0, 2}, {1, 3}, {4, 6}, {5, 7}, {0, 4}, {1, 5}, {2, 6}, {3, 7}};
	for (int32 Z = -1; Z < N; ++Z)
		for (int32 Y = -1; Y < N; ++Y)
			for (int32 X = -1; X < N; ++X)
			{
				float Dc[8];
				int32 Mask = 0;
				for (int32 K = 0; K < 8; ++K)
				{
					Dc[K] = 0.5f - Fc[CI(X + (K & 1), Y + ((K >> 1) & 1), Z + ((K >> 2) & 1))];   // > 0 air
					Mask |= (Dc[K] > 0.f) << K;
				}
				if (Mask == 0 || Mask == 255)
				{
					continue;
				}
				FVector Sum(0.f);
				int32 Cnt = 0;
				for (int32 E = 0; E < 12; ++E)
				{
					const int32 A = Edges[E][0], B = Edges[E][1];
					if ((Dc[A] > 0.f) != (Dc[B] > 0.f))
					{
						const float T = Dc[A] / (Dc[A] - Dc[B]);
						const FVector PA((A & 1), ((A >> 1) & 1), ((A >> 2) & 1));
						const FVector PB((B & 1), ((B >> 1) & 1), ((B >> 2) & 1));
						Sum += PA + (PB - PA) * T;
						++Cnt;
					}
				}
				const FVector Local = FVector(X, Y, Z) + Sum / Cnt;
				// normal: the fill gradient, pointing out of the ground
				const float Gx = (Dc[1] - Dc[0]) + (Dc[3] - Dc[2]) + (Dc[5] - Dc[4]) + (Dc[7] - Dc[6]);
				const float Gy = (Dc[2] - Dc[0]) + (Dc[3] - Dc[1]) + (Dc[6] - Dc[4]) + (Dc[7] - Dc[5]);
				const float Gz = (Dc[4] - Dc[0]) + (Dc[5] - Dc[1]) + (Dc[6] - Dc[2]) + (Dc[7] - Dc[3]);
				FVector Nrm(Gx, Gy, Gz);
				Nrm = Nrm.GetSafeNormal(1e-6f, FVector::UpVector);
				// soil: the solid corner nearest the surface
				int32 Best = -1;
				float BestD = -1e9f;
				for (int32 K = 0; K < 8; ++K)
				{
					if (Dc[K] <= 0.f && Dc[K] > BestD)
					{
						BestD = Dc[K];
						Best = K;
					}
				}
				const FIntVector CornerL(X + (Best & 1), Y + ((Best >> 1) & 1), Z + ((Best >> 2) & 1));
				uint8 Sv = Mc[CI(CornerL.X, CornerL.Y, CornerL.Z)];
				if (Sv == 0)
				{
					Sv = GenSoil(Base + CornerL);
				}
				VIdx[VI(X, Y, Z)] = Out.V.Num();
				const FVector Pos = (FVector(Base) + Local) * Vs;
				Out.V.Add(Pos);
				Out.N.Add(Nrm);
				Out.UV.Add(FVector2D(Pos.X, Pos.Y) / 100.f);
				Out.C.Add(SoilColor(Sv));
			}

	// one quad per point-to-point edge the surface crosses (edges starting at points 0 .. N-1)
	for (int32 Z = 0; Z < N; ++Z)
		for (int32 Y = 0; Y < N; ++Y)
			for (int32 X = 0; X < N; ++X)
			{
				const float D0 = 0.5f - Fc[CI(X, Y, Z)];
				for (int32 Ax = 0; Ax < 3; ++Ax)
				{
					const FIntVector Step(Ax == 0 ? 1 : 0, Ax == 1 ? 1 : 0, Ax == 2 ? 1 : 0);
					const float D1 = 0.5f - Fc[CI(X + Step.X, Y + Step.Y, Z + Step.Z)];
					if ((D0 > 0.f) == (D1 > 0.f))
					{
						continue;
					}
					// the two other axes, in cyclic order
					const FIntVector U(Ax == 1 ? 1 : 0, Ax == 2 ? 1 : 0, Ax == 0 ? 1 : 0);
					const FIntVector W(Ax == 2 ? 1 : 0, Ax == 0 ? 1 : 0, Ax == 1 ? 1 : 0);
					const FIntVector P(X, Y, Z);
					const FIntVector C00 = P - U - W, C10 = P - W, C11 = P, C01 = P - U;
					const int32 A = VIdx[VI(C00.X, C00.Y, C00.Z)];
					const int32 B = VIdx[VI(C10.X, C10.Y, C10.Z)];
					const int32 C = VIdx[VI(C11.X, C11.Y, C11.Z)];
					const int32 D = VIdx[VI(C01.X, C01.Y, C01.Z)];
					if (A == INDEX_NONE || B == INDEX_NONE || C == INDEX_NONE || D == INDEX_NONE)
					{
						continue;
					}
					// the face should look out of the ground: toward +axis if the ground is at P
					const FVector Want = FVector(Step) * ((D0 <= 0.f) ? 1.f : -1.f);
					const FVector Geo = FVector::CrossProduct(Out.V[B] - Out.V[A], Out.V[C] - Out.V[A]);
					bool bKeep = FVector::DotProduct(Geo, Want) > 0.f;
					if (bFlipWinding)
					{
						bKeep = !bKeep;
					}
					if (bKeep)
					{
						Out.T.Append({A, B, C, A, C, D});
					}
					else
					{
						Out.T.Append({A, C, B, A, D, C});
					}
				}
			}
}

void ABPVoxelTerrain::ApplyMesh(FBPVoxelChunk& Ch, FBPChunkMeshData& Data)
{
	if (!Ch.Mesh)
	{
		return;
	}
	if (Data.T.Num() == 0)
	{
		Ch.Mesh->ClearAllMeshSections();
		return;
	}
	Ch.Mesh->CreateMeshSection_LinearColor(0, Data.V, Data.T, Data.N, Data.UV, Data.C, TArray<FProcMeshTangent>(), true);
	if (Material)
	{
		Ch.Mesh->SetMaterial(0, Material);
	}
}

void ABPVoxelTerrain::BuildAll()
{
	const int32 N = ChunkCells;
	const float ChunkM = N * VoxelSize / 100.f;
	// make the chunks the surface passes through
	for (int32 CY = -HalfChunks; CY < HalfChunks; ++CY)
		for (int32 CX = -HalfChunks; CX < HalfChunks; ++CX)
		{
			float Lo = 1e9f, Hi = -1e9f;
			for (int32 J = 0; J <= 8; ++J)
				for (int32 I = 0; I <= 8; ++I)
				{
					const float H = GroundHeight((CX + I / 8.f) * ChunkM, (CY + J / 8.f) * ChunkM);
					Lo = FMath::Min(Lo, H);
					Hi = FMath::Max(Hi, H);
				}
			const int32 Z0 = FMath::FloorToInt((Lo - 1.f) / ChunkM);
			const int32 Z1 = FMath::FloorToInt((Hi + 1.f) / ChunkM);
			for (int32 CZ = Z0; CZ <= Z1; ++CZ)
			{
				GetOrCreateChunk(FIntVector(CX, CY, CZ));
			}
		}
	RemeshDirty();
	bBuilt = true;
	UE_LOG(LogBushPilot, Log, TEXT("Voxel ground: %d chunks, %.0f cm cells"), Chunks.Num(), VoxelSize);
}

void ABPVoxelTerrain::RemeshDirty()
{
	TArray<FBPVoxelChunk*> Dirty;
	for (auto& Pair : Chunks)
	{
		if (Pair.Value->bDirty)
		{
			Dirty.Add(Pair.Value.Get());
		}
	}
	if (Dirty.Num() == 0)
	{
		return;
	}
	TArray<FBPChunkMeshData> Data;
	Data.SetNum(Dirty.Num());
	ParallelFor(Dirty.Num(), [&](int32 K) { BuildMesh(Dirty[K]->Coord, Data[K]); });
	for (int32 K = 0; K < Dirty.Num(); ++K)
	{
		ApplyMesh(*Dirty[K], Data[K]);
		Dirty[K]->bDirty = false;
	}
}

// ---------------------------------------------------------------- play

void ABPVoxelTerrain::BeginPlay()
{
	Super::BeginPlay();
	if (!bBuilt)
	{
		BuildAll();
	}
}

void ABPVoxelTerrain::HandleTestInput(float DeltaSeconds)
{
	APlayerController* PC = GetWorld()->GetFirstPlayerController();
	if (!PC)
	{
		return;
	}
	if (PC->WasInputKeyJustPressed(EKeys::MouseScrollUp) || PC->WasInputKeyJustPressed(EKeys::RightBracket))
	{
		BrushRadius = FMath::Min(BrushRadius * 1.2f, 4.f);
	}
	if (PC->WasInputKeyJustPressed(EKeys::MouseScrollDown) || PC->WasInputKeyJustPressed(EKeys::LeftBracket))
	{
		BrushRadius = FMath::Max(BrushRadius / 1.2f, 0.3f);
	}
	FVector Eye;
	FRotator Rot;
	PC->GetPlayerViewPoint(Eye, Rot);
	FHitResult Hit;
	FCollisionQueryParams Q(SCENE_QUERY_STAT(BPDig), true);
	if (APawn* Pawn = PC->GetPawn())
	{
		Q.AddIgnoredActor(Pawn);
	}
	const bool bHit = GetWorld()->LineTraceSingleByChannel(Hit, Eye, Eye + Rot.Vector() * 6000.f, ECC_Visibility, Q);
	if (PC->WasInputKeyJustPressed(EKeys::B))
	{
		if (UStaticMesh* Rock = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Sphere.Sphere")))
		{
			FActorSpawnParameters SP;
			SP.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
			AStaticMeshActor* A = GetWorld()->SpawnActor<AStaticMeshActor>(Eye + Rot.Vector() * 400.f, FRotator::ZeroRotator, SP);
			A->SetMobility(EComponentMobility::Movable);
			A->GetStaticMeshComponent()->SetStaticMesh(Rock);
			A->SetActorScale3D(FVector(0.8f));
			A->GetStaticMeshComponent()->SetSimulatePhysics(true);
			A->GetStaticMeshComponent()->SetMassOverrideInKg(NAME_None, 900.f, true);
			A->GetStaticMeshComponent()->AddImpulse(Rot.Vector() * 2000.f, NAME_None, true);
		}
	}
	if (!bHit || Hit.GetActor() != this)
	{
		return;
	}
	DrawDebugSphere(GetWorld(), Hit.ImpactPoint, BrushRadius * 100.f, 16, FColor(255, 200, 80), false, -1.f, 0, 1.5f);
	const bool bDig = PC->IsInputKeyDown(EKeys::LeftMouseButton);
	const bool bDump = PC->IsInputKeyDown(EKeys::RightMouseButton);
	float Vol = 0.f;
	if (bDig)
	{
		Vol = Brush(Hit.ImpactPoint - Hit.ImpactNormal * BrushRadius * 30.f, BrushRadius, DigRate * DeltaSeconds);
	}
	else if (bDump)
	{
		Vol = -Brush(Hit.ImpactPoint + Hit.ImpactNormal * BrushRadius * 60.f, BrushRadius * 0.8f, -DigRate * DeltaSeconds);
	}
	LastVolume += Vol;
	if (GEngine)
	{
		static const TCHAR* Names[] = {TEXT("air"), TEXT("topsoil"), TEXT("sand"), TEXT("gravel"), TEXT("clay"), TEXT("pay gravel"),
			TEXT("rotten rock"), TEXT("bedrock"), TEXT("loose dirt")};
		const uint8 S = (uint8)SoilAt(Hit.ImpactPoint - Hit.ImpactNormal * VoxelSize * 0.6f);
		GEngine->AddOnScreenDebugMessage(77, 0.f, FColor::White,
			FString::Printf(TEXT("Ground: %s   brush %.1f m   moved %.1f m3   (LMB dig, RMB dump, wheel size, B boulder)"),
				Names[FMath::Min<int32>(S, 8)], BrushRadius, LastVolume));
	}
}

void ABPVoxelTerrain::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	if (!bBuilt)
	{
		BuildAll();
	}
	if (bTestControls)
	{
		HandleTestInput(DeltaSeconds);
	}
	SimAccum += DeltaSeconds;
	const float Step = 1.f / FMath::Max(SimRate, 1.f);
	int32 Steps = 0;
	while (SimAccum >= Step && Steps < 3)
	{
		SimAccum -= Step;
		SimStep();
		++Steps;
	}
	if (Steps == 3)
	{
		SimAccum = 0.f;
	}
	for (auto& Pair : Chunks)
	{
		Pair.Value->Active = FMath::Max(0.f, Pair.Value->Active - DeltaSeconds);
	}
	RemeshDirty();
}
