import tempfile
import unittest
from pathlib import Path

from app import CatalogStore, CatalogTrack, _fingerprint_similarity


class FingerprintSimilarityTest(unittest.TestCase):
    def test_identical_fingerprints_match(self) -> None:
        fingerprint = [0x12345678, -1, 0x00FF00FF, 17] * 8
        self.assertEqual(_fingerprint_similarity(fingerprint, fingerprint), 1.0)

    def test_small_temporal_offset_still_matches(self) -> None:
        fingerprint = list(range(80))
        shifted = [999, 998, 997] + fingerprint
        self.assertGreater(_fingerprint_similarity(fingerprint, shifted), 0.95)

    def test_unrelated_fingerprints_score_lower(self) -> None:
        left = [0] * 32
        right = [-1] * 32
        self.assertLess(_fingerprint_similarity(left, right), 0.1)


class CatalogStoreTest(unittest.IsolatedAsyncioTestCase):
    async def test_catalog_is_chunked_by_500_records(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = CatalogStore(Path(directory))
            await store.load()
            fingerprint = [[1, 2, 3, 4, 5, 6, 7, 8]]
            for index in range(501):
                await store.upsert(
                    CatalogTrack(
                        asset_id=f"asset-{index}",
                        title=f"Track {index}",
                        artist="",
                        owner_id="owner",
                        owner_name="Owner",
                        public_url="",
                        download_allowed=False,
                        save_allowed=True,
                        duration=12,
                        fingerprints=fingerprint,
                        updated_at=1,
                    )
                )
            chunks = sorted(Path(directory).glob("catalog_*.json"))
            self.assertEqual(len(chunks), 2)


if __name__ == "__main__":
    unittest.main()
