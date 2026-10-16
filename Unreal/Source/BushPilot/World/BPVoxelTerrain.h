#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "BPVoxelTerrain.generated.h"

class UProceduralMeshComponent;
class UMaterialInterface;

/** What a piece of ground is made of. Each one digs, slumps and looks different. */
UENUM(BlueprintType)
enum class EBPSoil : uint8
{
	Air = 0,
	Topsoil,     // moss, roots, organic: the top 20-40 cm; roots hold it
	Sand,        // runs, digs fast, slumps flat
	Gravel,      // river gravel
	Clay,        // slow and sticky, stands steep
	PayGravel,   // the gold-bearing gravel just above bedrock
	Weathered,   // rotten rock: breaks slowly
	Bedrock,     // hard rock: needs a breaker or blasting
	Loose,       // dirt that has been dug and moved (spoil, piles)
	Count
};

/**
 * One cube of ground (ChunkCells^3 points). Every point holds how full it is of
 * soil (0 empty .. 1 full) and what soil it is. Volume is conserved: dirt that
 * is dug goes into the bucket, dirt that slumps moves to the cells below.
 * Untouched chunks hold no data; they are computed from the generator.
 */
struct FBPVoxelChunk
{
	FIntVector Coord = FIntVector::ZeroValue;
	TArray<float> F;   // fill 0..1 per point
	TArray<uint8> M;   // soil per point
	UProceduralMeshComponent* Mesh = nullptr;
	bool bDirty = true;
	float Active = 0.f;     // seconds left to keep simulating (slumping / falling)
	bool HasData() const { return F.Num() > 0; }
};

/** Mesh data for one chunk, built on a worker thread. */
struct FBPChunkMeshData
{
	FIntVector Coord;
	TArray<FVector> V;
	TArray<int32> T;
	TArray<FVector> N;
	TArray<FVector2D> UV;
	TArray<FLinearColor> C;
};

/**
 * The diggable ground: smooth voxel terrain (surface nets) at 25 cm cells, in
 * chunks, with soil layers you dig through (topsoil, sand and gravel lenses,
 * clay, pay gravel on rotten rock, bedrock). The soil behaves like soil: cut a
 * wall in sand and it runs down to its natural slope, piles spill, loose dirt
 * falls into holes, overhangs in loose ground collapse. Rock stays put.
 * Mesh and collision update as it moves, so things stand on the real shape.
 *
 * Test controls (play in editor): left mouse digs, right mouse dumps dirt,
 * mouse wheel or [ ] sizes the brush, B drops a boulder.
 */
UCLASS()
class BUSHPILOT_API ABPVoxelTerrain : public AActor
{
	GENERATED_BODY()
public:
	ABPVoxelTerrain();

	/** Size of one cell (cm). 25 = the target; 10 for close-up detail later. */
	UPROPERTY(EditAnywhere, Category = "BushPilot|Ground")
	float VoxelSize = 25.f;

	/** Cells per chunk edge. */
	UPROPERTY(EditAnywhere, Category = "BushPilot|Ground")
	int32 ChunkCells = 32;

	/** The test area: chunks from -HalfChunks to HalfChunks-1 in X and Y. */
	UPROPERTY(EditAnywhere, Category = "BushPilot|Ground")
	int32 HalfChunks = 4;

	UPROPERTY(EditAnywhere, Category = "BushPilot|Ground")
	TObjectPtr<UMaterialInterface> Material;

	/** Fill removed per second at the brush centre in loose dirt. */
	UPROPERTY(EditAnywhere, Category = "BushPilot|Dig")
	float DigRate = 6.0f;

	UPROPERTY(EditAnywhere, Category = "BushPilot|Dig")
	float BrushRadius = 0.9f;

	/** Soil simulation steps per second (slumping, falling). */
	UPROPERTY(EditAnywhere, Category = "BushPilot|Dig")
	float SimRate = 30.f;

	UPROPERTY(EditAnywhere, Category = "BushPilot|Ground")
	bool bFlipWinding = true;

	/** The test controls (mouse dig / dump). Off in the real game; machines call Brush. */
	UPROPERTY(EditAnywhere, Category = "BushPilot|Dig")
	bool bTestControls = true;

	/** Dig (Amount > 0) or dump loose dirt (Amount < 0), in fill per point at the
	 *  centre, soft at the edge. Returns the volume moved (m^3, soil). */
	UFUNCTION(BlueprintCallable, Category = "BushPilot|Dig")
	float Brush(FVector WorldCenter, float RadiusM, float Amount);

	/** What the ground is made of at a world point. */
	UFUNCTION(BlueprintCallable, Category = "BushPilot|Dig")
	EBPSoil SoilAt(FVector WorldPoint) const;

	/** How hard a soil is to dig (1 = loose dirt, near 0 = solid rock). */
	static float Hardness(EBPSoil S);
	/** How readily it slides down a slope (0 = stands, 1 = runs like dry sand). */
	static float Mobility(EBPSoil S);
	/** Can it run out at a shallow angle (sand, spoil) rather than stopping at ~45 deg. */
	static bool Runs(EBPSoil S);

	virtual void Tick(float DeltaSeconds) override;

protected:
	virtual void BeginPlay() override;

	UPROPERTY(VisibleAnywhere)
	TObjectPtr<USceneComponent> Root;

	UPROPERTY(Transient)
	TArray<TObjectPtr<UProceduralMeshComponent>> MeshComponents;

	TMap<FIntVector, TUniquePtr<FBPVoxelChunk>> Chunks;
	bool bBuilt = false;
	float SimAccum = 0.f;
	int32 SimFrame = 0;
	float LastVolume = 0.f;

	// the untouched ground
	float GroundHeight(float Xm, float Ym) const;
	float GenFill(const FIntVector& P) const;
	void GroundColumn(int32 PX, int32 PY, float& OutH, float& OutCos) const;
	float FillFromColumn(float H, float Cos, int32 PZ) const;
	uint8 GenSoil(const FIntVector& P) const;

	// access
	FIntVector ChunkOf(const FIntVector& P) const;
	FIntVector LocalOf(const FIntVector& P, const FIntVector& C) const { return P - C * ChunkCells; }
	int32 Index(const FIntVector& L) const { return L.X + ChunkCells * (L.Y + ChunkCells * L.Z); }
	bool InArea(const FIntVector& C) const { return C.X >= -HalfChunks && C.X < HalfChunks && C.Y >= -HalfChunks && C.Y < HalfChunks; }
	FBPVoxelChunk* FindChunk(const FIntVector& C) const;
	FBPVoxelChunk* GetOrCreateChunk(const FIntVector& C);
	void EnsureData(FBPVoxelChunk& Ch) const;
	float Fill(const FIntVector& P) const;
	uint8 Soil(const FIntVector& P) const;
	/** Writable point (makes the chunk's data); null outside the area. */
	bool PointRef(const FIntVector& P, float*& OutF, uint8*& OutM);
	void Touch(const FIntVector& P, float ActiveSeconds = 2.f);

	// mesh
	void BuildMesh(const FIntVector& C, FBPChunkMeshData& Out) const;
	void ApplyMesh(FBPVoxelChunk& Ch, FBPChunkMeshData& Data);
	void BuildAll();
	void RemeshDirty();

	// soil behaviour
	void SimStep();
	bool MoveSoil(const FIntVector& From, const FIntVector& To, float Amount);

	void HandleTestInput(float DeltaSeconds);
};
