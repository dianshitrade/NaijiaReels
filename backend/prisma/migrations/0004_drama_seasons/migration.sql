-- CreateTable
CREATE TABLE "drama_seasons" (
    "id" TEXT NOT NULL,
    "drama_id" TEXT NOT NULL,
    "season_no" INTEGER NOT NULL,
    "title" TEXT,
    "cover_path" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "drama_seasons_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "drama_seasons_drama_id_season_no_key" ON "drama_seasons"("drama_id", "season_no");

-- AddForeignKey
ALTER TABLE "drama_seasons" ADD CONSTRAINT "drama_seasons_drama_id_fkey" FOREIGN KEY ("drama_id") REFERENCES "dramas"("id") ON DELETE CASCADE ON UPDATE CASCADE;
