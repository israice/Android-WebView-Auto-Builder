.class public final Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;
.super Lcom/google/android/material/carousel/CarouselStrategy;
.source "MultiBrowseCarouselStrategy.java"


# annotations
.annotation system Ldalvik/annotation/MemberClasses;
    value = {
        Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;
    }
.end annotation


# static fields
.field private static final MEDIUM_COUNTS:[I

.field private static final MEDIUM_COUNTS_COMPACT:[I

.field private static final MEDIUM_ITEM_FLEX_PERCENTAGE:F = 0.1f

.field private static final SMALL_COUNTS:[I


# instance fields
.field private final forceCompactArrangement:Z


# direct methods
.method static constructor <clinit>()V
    .locals 2

    .line 55
    const/4 v0, 0x1

    filled-new-array {v0}, [I

    move-result-object v1

    sput-object v1, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->SMALL_COUNTS:[I

    .line 56
    const/4 v1, 0x0

    filled-new-array {v0, v1}, [I

    move-result-object v0

    sput-object v0, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->MEDIUM_COUNTS:[I

    .line 57
    filled-new-array {v1}, [I

    move-result-object v0

    sput-object v0, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->MEDIUM_COUNTS_COMPACT:[I

    return-void
.end method

.method public constructor <init>()V
    .locals 1

    .line 67
    const/4 v0, 0x0

    invoke-direct {p0, v0}, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;-><init>(Z)V

    .line 68
    return-void
.end method

.method public constructor <init>(Z)V
    .locals 0
    .param p1, "forceCompactArrangement"    # Z

    .line 79
    invoke-direct {p0}, Lcom/google/android/material/carousel/CarouselStrategy;-><init>()V

    .line 80
    iput-boolean p1, p0, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->forceCompactArrangement:Z

    .line 81
    return-void
.end method

.method private static findLowestCostArrangement(FFFF[IF[IF[I)Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;
    .locals 27
    .param p0, "availableSpace"    # F
    .param p1, "targetSmallSize"    # F
    .param p2, "minSmallSize"    # F
    .param p3, "maxSmallSize"    # F
    .param p4, "smallCounts"    # [I
    .param p5, "targetMediumSize"    # F
    .param p6, "mediumCounts"    # [I
    .param p7, "targetLargeSize"    # F
    .param p8, "largeCounts"    # [I

    .line 227
    move-object/from16 v0, p4

    move-object/from16 v1, p6

    move-object/from16 v2, p8

    const/4 v3, 0x0

    .line 228
    .local v3, "lowestCostArrangement":Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;
    const/4 v4, 0x1

    .line 229
    .local v4, "priority":I
    array-length v5, v2

    const/4 v6, 0x0

    move v7, v6

    :goto_0
    if-ge v7, v5, :cond_4

    aget v19, v2, v7

    .line 230
    .local v19, "largeCount":I
    array-length v15, v1

    move v14, v6

    :goto_1
    if-ge v14, v15, :cond_3

    aget v20, v1, v14

    .line 231
    .local v20, "mediumCount":I
    array-length v13, v0

    move v12, v6

    :goto_2
    if-ge v12, v13, :cond_2

    aget v21, v0, v12

    .line 232
    .local v21, "smallCount":I
    new-instance v22, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;

    move-object/from16 v8, v22

    move v9, v4

    move/from16 v10, p1

    move/from16 v11, p2

    move/from16 v23, v12

    move/from16 v12, p3

    move/from16 v24, v13

    move/from16 v13, v21

    move/from16 v25, v14

    move/from16 v14, p5

    move/from16 v26, v15

    move/from16 v15, v20

    move/from16 v16, p7

    move/from16 v17, v19

    move/from16 v18, p0

    invoke-direct/range {v8 .. v18}, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;-><init>(IFFFIFIFIF)V

    .line 244
    .local v8, "arrangement":Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;
    if-eqz v3, :cond_0

    iget v9, v8, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->cost:F

    iget v10, v3, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->cost:F

    cmpg-float v9, v9, v10

    if-gez v9, :cond_1

    .line 245
    :cond_0
    move-object v3, v8

    .line 246
    iget v9, v3, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->cost:F

    const/4 v10, 0x0

    cmpl-float v9, v9, v10

    if-nez v9, :cond_1

    .line 251
    return-object v3

    .line 254
    :cond_1
    nop

    .end local v8    # "arrangement":Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;
    .end local v21    # "smallCount":I
    add-int/lit8 v4, v4, 0x1

    .line 231
    add-int/lit8 v12, v23, 0x1

    move/from16 v13, v24

    move/from16 v14, v25

    move/from16 v15, v26

    goto :goto_2

    :cond_2
    move/from16 v25, v14

    move/from16 v26, v15

    .line 230
    .end local v20    # "mediumCount":I
    add-int/lit8 v14, v25, 0x1

    goto :goto_1

    .line 229
    .end local v19    # "largeCount":I
    :cond_3
    add-int/lit8 v7, v7, 0x1

    goto :goto_0

    .line 258
    :cond_4
    return-object v3
.end method

.method private getExtraSmallSize(Landroid/content/Context;)F
    .locals 2
    .param p1, "context"    # Landroid/content/Context;

    .line 84
    invoke-virtual {p1}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;

    move-result-object v0

    sget v1, Lcom/google/android/material/R$dimen;->m3_carousel_gone_size:I

    invoke-virtual {v0, v1}, Landroid/content/res/Resources;->getDimension(I)F

    move-result v0

    return v0
.end method

.method private getSmallSizeMax(Landroid/content/Context;)F
    .locals 2
    .param p1, "context"    # Landroid/content/Context;

    .line 92
    invoke-virtual {p1}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;

    move-result-object v0

    sget v1, Lcom/google/android/material/R$dimen;->m3_carousel_small_item_size_max:I

    invoke-virtual {v0, v1}, Landroid/content/res/Resources;->getDimension(I)F

    move-result v0

    return v0
.end method

.method private getSmallSizeMin(Landroid/content/Context;)F
    .locals 2
    .param p1, "context"    # Landroid/content/Context;

    .line 88
    invoke-virtual {p1}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;

    move-result-object v0

    sget v1, Lcom/google/android/material/R$dimen;->m3_carousel_small_item_size_min:I

    invoke-virtual {v0, v1}, Landroid/content/res/Resources;->getDimension(I)F

    move-result v0

    return v0
.end method

.method private static maxValue([I)I
    .locals 4
    .param p0, "array"    # [I

    .line 262
    const/high16 v0, -0x80000000

    .line 263
    .local v0, "largest":I
    array-length v1, p0

    const/4 v2, 0x0

    :goto_0
    if-ge v2, v1, :cond_1

    aget v3, p0, v2

    .line 264
    .local v3, "j":I
    if-le v3, v0, :cond_0

    .line 265
    move v0, v3

    .line 263
    .end local v3    # "j":I
    :cond_0
    add-int/lit8 v2, v2, 0x1

    goto :goto_0

    .line 269
    :cond_1
    return v0
.end method


# virtual methods
.method onFirstChildMeasuredWithMargins(Lcom/google/android/material/carousel/Carousel;Landroid/view/View;)Lcom/google/android/material/carousel/KeylineState;
    .locals 36
    .param p1, "carousel"    # Lcom/google/android/material/carousel/Carousel;
    .param p2, "child"    # Landroid/view/View;

    .line 98
    move-object/from16 v0, p0

    invoke-interface/range {p1 .. p1}, Lcom/google/android/material/carousel/Carousel;->getContainerWidth()I

    move-result v1

    int-to-float v1, v1

    .line 100
    .local v1, "availableSpace":F
    invoke-virtual/range {p2 .. p2}, Landroid/view/View;->getLayoutParams()Landroid/view/ViewGroup$LayoutParams;

    move-result-object v2

    move-object v11, v2

    check-cast v11, Landroidx/recyclerview/widget/RecyclerView$LayoutParams;

    .line 101
    .local v11, "childLayoutParams":Landroidx/recyclerview/widget/RecyclerView$LayoutParams;
    iget v2, v11, Landroidx/recyclerview/widget/RecyclerView$LayoutParams;->leftMargin:I

    iget v3, v11, Landroidx/recyclerview/widget/RecyclerView$LayoutParams;->rightMargin:I

    add-int/2addr v2, v3

    int-to-float v12, v2

    .line 103
    .local v12, "childHorizontalMargins":F
    invoke-virtual/range {p2 .. p2}, Landroid/view/View;->getContext()Landroid/content/Context;

    move-result-object v2

    invoke-direct {v0, v2}, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->getSmallSizeMin(Landroid/content/Context;)F

    move-result v2

    add-float v13, v2, v12

    .line 104
    .local v13, "smallChildWidthMin":F
    invoke-virtual/range {p2 .. p2}, Landroid/view/View;->getContext()Landroid/content/Context;

    move-result-object v2

    invoke-direct {v0, v2}, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->getSmallSizeMax(Landroid/content/Context;)F

    move-result v2

    add-float v14, v2, v12

    .line 106
    .local v14, "smallChildWidthMax":F
    invoke-virtual/range {p2 .. p2}, Landroid/view/View;->getMeasuredWidth()I

    move-result v2

    int-to-float v15, v2

    .line 107
    .local v15, "measuredChildWidth":F
    add-float v2, v15, v12

    invoke-static {v2, v1}, Ljava/lang/Math;->min(FF)F

    move-result v16

    .line 112
    .local v16, "targetLargeChildWidth":F
    const/high16 v2, 0x40400000    # 3.0f

    div-float v2, v15, v2

    add-float/2addr v2, v12

    .line 115
    invoke-virtual/range {p2 .. p2}, Landroid/view/View;->getContext()Landroid/content/Context;

    move-result-object v3

    invoke-direct {v0, v3}, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->getSmallSizeMin(Landroid/content/Context;)F

    move-result v3

    add-float/2addr v3, v12

    .line 116
    invoke-virtual/range {p2 .. p2}, Landroid/view/View;->getContext()Landroid/content/Context;

    move-result-object v4

    invoke-direct {v0, v4}, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->getSmallSizeMax(Landroid/content/Context;)F

    move-result v4

    add-float/2addr v4, v12

    .line 113
    invoke-static {v2, v3, v4}, Landroidx/core/math/MathUtils;->clamp(FFF)F

    move-result v17

    .line 117
    .local v17, "targetSmallChildWidth":F
    add-float v2, v16, v17

    const/high16 v18, 0x40000000    # 2.0f

    div-float v19, v2, v18

    .line 123
    .local v19, "targetMediumChildWidth":F
    sget-object v20, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->SMALL_COUNTS:[I

    .line 124
    .local v20, "smallCounts":[I
    iget-boolean v2, v0, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->forceCompactArrangement:Z

    if-eqz v2, :cond_0

    sget-object v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->MEDIUM_COUNTS_COMPACT:[I

    goto :goto_0

    :cond_0
    sget-object v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->MEDIUM_COUNTS:[I

    :goto_0
    move-object v8, v2

    .line 127
    .local v8, "mediumCounts":[I
    nop

    .line 129
    invoke-static {v8}, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->maxValue([I)I

    move-result v2

    int-to-float v2, v2

    mul-float v2, v2, v19

    sub-float v2, v1, v2

    .line 130
    invoke-static/range {v20 .. v20}, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->maxValue([I)I

    move-result v3

    int-to-float v3, v3

    mul-float/2addr v3, v14

    sub-float v21, v2, v3

    .line 131
    .local v21, "minAvailableLargeSpace":F
    div-float v2, v21, v16

    float-to-double v2, v2

    invoke-static {v2, v3}, Ljava/lang/Math;->floor(D)D

    move-result-wide v2

    const-wide/high16 v4, 0x3ff0000000000000L    # 1.0

    invoke-static {v4, v5, v2, v3}, Ljava/lang/Math;->max(DD)D

    move-result-wide v2

    double-to-int v10, v2

    .line 132
    .local v10, "largeCountMin":I
    div-float v2, v1, v16

    float-to-double v2, v2

    invoke-static {v2, v3}, Ljava/lang/Math;->ceil(D)D

    move-result-wide v2

    double-to-int v9, v2

    .line 133
    .local v9, "largeCountMax":I
    sub-int v2, v9, v10

    add-int/lit8 v2, v2, 0x1

    new-array v7, v2, [I

    .line 134
    .local v7, "largeCounts":[I
    const/4 v2, 0x0

    .local v2, "i":I
    :goto_1
    array-length v3, v7

    if-ge v2, v3, :cond_1

    .line 135
    sub-int v3, v9, v2

    aput v3, v7, v2

    .line 134
    add-int/lit8 v2, v2, 0x1

    goto :goto_1

    .line 138
    .end local v2    # "i":I
    :cond_1
    nop

    .line 139
    move v2, v1

    move/from16 v3, v17

    move v4, v13

    move v5, v14

    move-object/from16 v6, v20

    move-object/from16 v22, v7

    .end local v7    # "largeCounts":[I
    .local v22, "largeCounts":[I
    move/from16 v7, v19

    move/from16 v23, v9

    .end local v9    # "largeCountMax":I
    .local v23, "largeCountMax":I
    move/from16 v9, v16

    move/from16 v24, v10

    .end local v10    # "largeCountMin":I
    .local v24, "largeCountMin":I
    move-object/from16 v10, v22

    invoke-static/range {v2 .. v10}, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->findLowestCostArrangement(FFFF[IF[IF[I)Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;

    move-result-object v2

    .line 150
    .local v2, "arrangement":Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;
    invoke-virtual/range {p2 .. p2}, Landroid/view/View;->getContext()Landroid/content/Context;

    move-result-object v3

    invoke-direct {v0, v3}, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->getExtraSmallSize(Landroid/content/Context;)F

    move-result v3

    add-float/2addr v3, v12

    .line 152
    .local v3, "extraSmallChildWidth":F
    const/4 v4, 0x0

    .line 153
    .local v4, "start":F
    div-float v5, v3, v18

    sub-float v5, v4, v5

    .line 155
    .local v5, "extraSmallHeadCenterX":F
    iget v6, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->largeSize:F

    div-float v6, v6, v18

    add-float/2addr v6, v4

    .line 156
    .local v6, "largeStartCenterX":F
    iget v7, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->largeCount:I

    add-int/lit8 v7, v7, -0x1

    .line 157
    const/4 v9, 0x0

    invoke-static {v9, v7}, Ljava/lang/Math;->max(II)I

    move-result v7

    int-to-float v7, v7

    iget v9, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->largeSize:F

    mul-float/2addr v7, v9

    add-float/2addr v7, v6

    .line 158
    .local v7, "largeEndCenterX":F
    iget v9, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->largeSize:F

    div-float v9, v9, v18

    add-float/2addr v9, v7

    .line 161
    .end local v4    # "start":F
    .local v9, "start":F
    iget v4, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->mediumCount:I

    if-lez v4, :cond_2

    iget v4, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->mediumSize:F

    div-float v4, v4, v18

    add-float/2addr v4, v9

    goto :goto_2

    :cond_2
    move v4, v7

    .line 162
    .local v4, "mediumCenterX":F
    :goto_2
    iget v10, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->mediumCount:I

    if-lez v10, :cond_3

    iget v10, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->mediumSize:F

    div-float v10, v10, v18

    add-float/2addr v10, v4

    goto :goto_3

    :cond_3
    move v10, v9

    :goto_3
    move v9, v10

    .line 165
    iget v10, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->smallCount:I

    if-lez v10, :cond_4

    iget v10, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->smallSize:F

    div-float v10, v10, v18

    add-float/2addr v10, v9

    goto :goto_4

    :cond_4
    move v10, v4

    .line 167
    .local v10, "smallStartCenterX":F
    :goto_4
    invoke-interface/range {p1 .. p1}, Lcom/google/android/material/carousel/Carousel;->getContainerWidth()I

    move-result v0

    int-to-float v0, v0

    div-float v18, v3, v18

    add-float v0, v0, v18

    .line 169
    .local v0, "extraSmallTailCenterX":F
    move/from16 v18, v1

    .end local v1    # "availableSpace":F
    .local v18, "availableSpace":F
    iget v1, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->largeSize:F

    .line 170
    invoke-static {v3, v1, v12}, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->getChildMaskPercentage(FFF)F

    move-result v1

    .line 171
    .local v1, "extraSmallMask":F
    move/from16 v31, v7

    .end local v7    # "largeEndCenterX":F
    .local v31, "largeEndCenterX":F
    iget v7, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->smallSize:F

    move-object/from16 v32, v8

    .end local v8    # "mediumCounts":[I
    .local v32, "mediumCounts":[I
    iget v8, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->largeSize:F

    .line 172
    invoke-static {v7, v8, v12}, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->getChildMaskPercentage(FFF)F

    move-result v7

    .line 174
    .local v7, "smallMask":F
    iget v8, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->mediumSize:F

    move/from16 v33, v9

    .end local v9    # "start":F
    .local v33, "start":F
    iget v9, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->largeSize:F

    .line 175
    invoke-static {v8, v9, v12}, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy;->getChildMaskPercentage(FFF)F

    move-result v8

    .line 177
    .local v8, "mediumMask":F
    const/4 v9, 0x0

    .line 179
    .local v9, "largeMask":F
    move-object/from16 v34, v11

    .end local v11    # "childLayoutParams":Landroidx/recyclerview/widget/RecyclerView$LayoutParams;
    .local v34, "childLayoutParams":Landroidx/recyclerview/widget/RecyclerView$LayoutParams;
    new-instance v11, Lcom/google/android/material/carousel/KeylineState$Builder;

    move/from16 v35, v12

    .end local v12    # "childHorizontalMargins":F
    .local v35, "childHorizontalMargins":F
    iget v12, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->largeSize:F

    invoke-direct {v11, v12}, Lcom/google/android/material/carousel/KeylineState$Builder;-><init>(F)V

    .line 181
    invoke-virtual {v11, v5, v1, v3}, Lcom/google/android/material/carousel/KeylineState$Builder;->addKeyline(FFF)Lcom/google/android/material/carousel/KeylineState$Builder;

    move-result-object v25

    iget v11, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->largeSize:F

    iget v12, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->largeCount:I

    const/16 v30, 0x1

    .line 182
    move/from16 v26, v6

    move/from16 v27, v9

    move/from16 v28, v11

    move/from16 v29, v12

    invoke-virtual/range {v25 .. v30}, Lcom/google/android/material/carousel/KeylineState$Builder;->addKeylineRange(FFFIZ)Lcom/google/android/material/carousel/KeylineState$Builder;

    move-result-object v11

    .line 184
    .local v11, "builder":Lcom/google/android/material/carousel/KeylineState$Builder;
    iget v12, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->mediumCount:I

    if-lez v12, :cond_5

    .line 185
    iget v12, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->mediumSize:F

    invoke-virtual {v11, v4, v8, v12}, Lcom/google/android/material/carousel/KeylineState$Builder;->addKeyline(FFF)Lcom/google/android/material/carousel/KeylineState$Builder;

    .line 187
    :cond_5
    iget v12, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->smallCount:I

    if-lez v12, :cond_6

    .line 188
    iget v12, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->smallSize:F

    move/from16 v25, v4

    .end local v4    # "mediumCenterX":F
    .local v25, "mediumCenterX":F
    iget v4, v2, Lcom/google/android/material/carousel/MultiBrowseCarouselStrategy$Arrangement;->smallCount:I

    invoke-virtual {v11, v10, v7, v12, v4}, Lcom/google/android/material/carousel/KeylineState$Builder;->addKeylineRange(FFFI)Lcom/google/android/material/carousel/KeylineState$Builder;

    goto :goto_5

    .line 187
    .end local v25    # "mediumCenterX":F
    .restart local v4    # "mediumCenterX":F
    :cond_6
    move/from16 v25, v4

    .line 191
    .end local v4    # "mediumCenterX":F
    .restart local v25    # "mediumCenterX":F
    :goto_5
    invoke-virtual {v11, v0, v1, v3}, Lcom/google/android/material/carousel/KeylineState$Builder;->addKeyline(FFF)Lcom/google/android/material/carousel/KeylineState$Builder;

    .line 192
    invoke-virtual {v11}, Lcom/google/android/material/carousel/KeylineState$Builder;->build()Lcom/google/android/material/carousel/KeylineState;

    move-result-object v4

    return-object v4
.end method
