import Testing
import Foundation
@testable import myCoder

/// Пул API-ключей провайдера — обычный список: один ключ в поле, добавляется
/// кнопкой «+», пустой текст — это отсутствие ключа, а не пустая строка.
///
/// Первый ключ списка — основной (primary), он уходит в провайдера;
/// остальные хранятся в пуле `ProviderAPIKeyPoolStore`.
@Suite("Пул API-ключей: список вместо текстового поля")
struct ProviderAPIKeyListLogicTests {

    // MARK: - Загрузка (fullList)

    @Test("Пустой провайдер открывается с одним пустым полем")
    func emptyProviderStartsWithOneBlankRow() {
        let list = ProviderAPIKeyListLogic.fullList(primary: nil, pool: [])
        #expect(list == [""])
    }

    @Test("Основной ключ становится первой строкой, пул идёт за ним")
    func primaryComesFirst() {
        let list = ProviderAPIKeyListLogic.fullList(primary: "sk-primary", pool: ["sk-2", "sk-3"])
        #expect(list == ["sk-primary", "sk-2", "sk-3"])
    }

    @Test("Пробелы вокруг ключей обрезаются при загрузке")
    func whitespaceIsTrimmedOnLoad() {
        let list = ProviderAPIKeyListLogic.fullList(primary: "  sk-1  ", pool: ["\tsk-2\n", "   "])
        #expect(list == ["sk-1", "sk-2"])
    }

    @Test("Пустой основной ключ не занимает место в списке")
    func blankPrimaryIsDropped() {
        let list = ProviderAPIKeyListLogic.fullList(primary: "   ", pool: ["sk-2"])
        #expect(list == ["sk-2"])
    }

    @Test("Дубликаты не появляются в списке дважды")
    func duplicatesAreCollapsed() {
        let list = ProviderAPIKeyListLogic.fullList(primary: "sk-1", pool: ["sk-1", "sk-2", "sk-2"])
        #expect(list == ["sk-1", "sk-2"])
    }

    @Test("Пустые строки пула схлопываются, поле остаётся одно")
    func blankPoolRowsCollapse() {
        let list = ProviderAPIKeyListLogic.fullList(primary: nil, pool: ["  ", "\n", ""])
        #expect(list == [""])
    }

    // MARK: - Сохранение (split)

    @Test("Первая строка становится основным ключом, остальные — пулом")
    func firstRowBecomesPrimary() {
        let split = ProviderAPIKeyListLogic.split(list: ["sk-a", "sk-b", "sk-c"])
        #expect(split.primary == "sk-a")
        #expect(split.pool == ["sk-b", "sk-c"])
    }

    @Test("Пустая первая строка пропускается, остальные строки поднимаются")
    func blankFirstRowIsSkipped() {
        let split = ProviderAPIKeyListLogic.split(list: ["", "sk-b", ""])
        #expect(split.primary == "sk-b")
        #expect(split.pool.isEmpty)
    }

    @Test("Пустой список сохраняется как отсутствие ключа")
    func fullyEmptyListHasNoKey() {
        let split = ProviderAPIKeyListLogic.split(list: ["  ", "\t", ""])
        #expect(split.primary.isEmpty)
        #expect(split.pool.isEmpty)
    }

    @Test("Пробелы вокруг строк обрезаются при сохранении")
    func whitespaceIsTrimmedOnSave() {
        let split = ProviderAPIKeyListLogic.split(list: ["  sk-a  ", " sk-b ", "  "])
        #expect(split.primary == "sk-a")
        #expect(split.pool == ["sk-b"])
    }

    @Test("Дубликаты не сохраняются дважды")
    func duplicatesAreDroppedOnSave() {
        let split = ProviderAPIKeyListLogic.split(list: ["sk-a", "sk-b", "sk-a"])
        #expect(split.primary == "sk-a")
        #expect(split.pool == ["sk-b"])
    }
}
