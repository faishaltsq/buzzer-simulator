import glob
import re

specs = glob.glob("tests/Specs/*.spec.luau")
print(f"Total spec files found: {len(specs)}")

total_tests = 0
total_assertions = 0

assertion_patterns = [
    r"\bexpectEqual\(",
    r"\bexpectTrue\(",
    r"\bexpectFalse\(",
    r"\bassert\(",
    r"\bequal\(",
    r"\bassertOk\(",
    r"\bassertFail\(",
]

test_pattern = r'test\s*\(\s*["\']'

for spec_path in sorted(specs):
    with open(spec_path, "r", encoding="utf-8") as f:
        content = f.read()
    
    tests = len(re.findall(test_pattern, content))
    assertions = 0
    for pat in assertion_patterns:
        assertions += len(re.findall(pat, content))
    
    total_tests += tests
    total_assertions += assertions
    print(f"  {spec_path}: {tests} tests, ~{assertions} assertions")

print(f"\nTOTAL: {len(specs)} spec suites, {total_tests} tests, ~{total_assertions} assertions.")
