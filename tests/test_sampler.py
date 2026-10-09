import unittest
from pathlib import Path

from modules.data import BalancedDomainBatchSampler, Sample


class BalancedDomainBatchSamplerTest(unittest.TestCase):
    def test_each_batch_has_equal_domains(self):
        samples = []
        for label in range(73):
            samples.append(Sample(Path("expert"), label, f"WORD{label:04d}", "expert", "e"))
            samples.append(Sample(Path("team"), label, f"WORD{label:04d}", "team", "t"))
        sampler = BalancedDomainBatchSampler(samples, batch_size=10)

        batch = next(iter(sampler))
        domains = [samples[index].domain for index in batch]

        self.assertEqual(domains.count("expert"), 5)
        self.assertEqual(domains.count("team"), 5)


if __name__ == "__main__":
    unittest.main()
