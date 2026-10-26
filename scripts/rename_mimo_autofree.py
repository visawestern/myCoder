from pathlib import Path

root = Path('/home/ubuntu/MyCoder')
paths = list((root / 'MyCoder' / 'Sources').rglob('*.swift')) + list((root / 'MyCoder' / 'Tests').rglob('*.swift'))
replacements = [
    ('MiMoAutoProviderStore', 'MyCoderAutoFreeStore'),
    ('MiMoAutoProvider', 'MyCoderAutoFreeProvider'),
    ('MiMoAutoClient', 'MyCoderAutoFreeClient'),
    ('MiMoAutoError', 'MyCoderAutoFreeError'),
    ('MiMoAuto', 'MyCoderAutoFree'),
    ('mimoAuto', 'autoFree'),
    ('mimo-auto', 'mycoder-auto-free'),
    ('MiMo Auto', 'MyCoder Auto Free'),
]
for path in paths:
    text = path.read_text()
    updated = text
    for old, new in replacements:
        updated = updated.replace(old, new)
    if updated != text:
        path.write_text(updated)

# The two implementation filenames are part of the public source map.
for old, new in [
    ('MiMoAutoClient.swift', 'MyCoderAutoFreeClient.swift'),
    ('MiMoAutoProvider.swift', 'MyCoderAutoFreeProvider.swift'),
    ('MiMoAutoProviderTests.swift', 'MyCoderAutoFreeProviderTests.swift'),
]:
    old_path = root / 'MyCoder' / ('Tests' if 'Tests' in old else 'Sources/Services') / old
    new_path = old_path.with_name(new)
    if old_path.exists() and not new_path.exists():
        old_path.rename(new_path)
