import Testing
import Foundation
@testable import myCoder

@Suite("Symbol name extractor — объявления функций/типов/переменных")
struct SymbolNameExtractorTests {

    @Test("Swift: функции, типы и переменные с номерами строк")
    func swiftDeclarations() {
        let source = """
        import Foundation

        /// Документация хранителя.
        final class ProviderStore {
            private var cache: [String: Int] = [:]

            func load(id: String) -> Int {
                cache[id] ?? 0
            }

            struct Entry {
                let key: String
            }
        }
        """
        let declarations = SymbolNameExtractor.declarations(in: source, language: "swift")
        let names = declarations.map(\.name)
        #expect(names.contains("ProviderStore"))
        #expect(names.contains("load"))
        #expect(names.contains("Entry"))
        #expect(names.contains("cache"))
        #expect(declarations.first(where: { $0.name == "ProviderStore" })?.kind == "type")
        #expect(declarations.first(where: { $0.name == "load" })?.kind == "func")
        #expect(declarations.first(where: { $0.name == "cache" })?.kind == "var")
        #expect(declarations.first(where: { $0.name == "ProviderStore" })?.line == 4)
    }

    @Test("Swift: объявления внутри строк и комментариев не попадают в список")
    func swiftIgnoresStringsAndComments() {
        let source = """
        // func commentedOut() {}
        let sample = "func alsoCommented() {}"
        /* func blockCommented() {} */
        func real() {}
        """
        let names = SymbolNameExtractor.declarations(in: source, language: "swift").map(\.name)
        #expect(names.contains("real"))
        #expect(!names.contains("commentedOut"))
        #expect(!names.contains("alsoCommented"))
        #expect(!names.contains("blockCommented"))
    }

    @Test("Python: функции и классы")
    func pythonDeclarations() {
        let source = """
        import os

        class SearchService:
            def query(self, term):
                # def helper():
                return term

        def build_index(path):
            return None
        """
        let declarations = SymbolNameExtractor.declarations(in: source, language: "python")
        #expect(declarations.contains(SymbolDeclaration(name: "SearchService", kind: "type", line: 3)))
        #expect(declarations.contains(SymbolDeclaration(name: "query", kind: "func", line: 4)))
        #expect(declarations.contains(SymbolDeclaration(name: "build_index", kind: "func", line: 8)))
        #expect(!declarations.contains { $0.name == "helper" })
    }

    @Test("JavaScript/TypeScript: function, const, class")
    func javascriptDeclarations() {
        let source = """
        export class Engine {
            start() {}
        }
        export function boot(engine) {
            return engine.start();
        }
        const helper = (x) => x * 2;
        let counter = 0;
        """
        let declarations = SymbolNameExtractor.declarations(in: source, language: "javascript")
        #expect(declarations.contains(SymbolDeclaration(name: "Engine", kind: "type", line: 1)))
        #expect(declarations.contains(SymbolDeclaration(name: "boot", kind: "func", line: 4)))
        #expect(declarations.contains(SymbolDeclaration(name: "helper", kind: "var", line: 7)))
        #expect(declarations.contains(SymbolDeclaration(name: "counter", kind: "var", line: 8)))
    }

    @Test("Go: функции, методы и структуры")
    func goDeclarations() {
        let source = """
        package main

        type Server struct {
            port int
        }

        func (s *Server) Start() error {
            return nil
        }

        func main() {
            _ = Server{}
        }
        """
        let declarations = SymbolNameExtractor.declarations(in: source, language: "go")
        #expect(declarations.contains(SymbolDeclaration(name: "Server", kind: "type", line: 3)))
        #expect(declarations.contains(SymbolDeclaration(name: "Start", kind: "func", line: 7)))
        #expect(declarations.contains(SymbolDeclaration(name: "main", kind: "func", line: 11)))
    }

    @Test("Rust: fn, struct, enum, trait")
    func rustDeclarations() {
        let source = """
        pub struct Engine {
            id: u32,
        }

        pub enum Mode {
            Fast,
        }

        trait Runner {
            fn run(&self);
        }

        fn main() {}
        """
        let declarations = SymbolNameExtractor.declarations(in: source, language: "rust")
        #expect(declarations.contains(SymbolDeclaration(name: "Engine", kind: "type", line: 1)))
        #expect(declarations.contains(SymbolDeclaration(name: "Mode", kind: "type", line: 5)))
        #expect(declarations.contains(SymbolDeclaration(name: "Runner", kind: "type", line: 9)))
        #expect(declarations.contains(SymbolDeclaration(name: "run", kind: "func", line: 10)))
        #expect(declarations.contains(SymbolDeclaration(name: "main", kind: "func", line: 13)))
    }

    @Test("C/Java: функции и классы")
    func cLikeDeclarations() {
        let source = """
        class Cache {
        };

        int compute(int value) {
            return value;
        }
        """
        let declarations = SymbolNameExtractor.declarations(in: source, language: "java")
        #expect(declarations.contains(SymbolDeclaration(name: "Cache", kind: "type", line: 1)))
        #expect(declarations.contains(SymbolDeclaration(name: "compute", kind: "func", line: 4)))
    }

    @Test("Неизвестный язык не выдаёт объявлений и не падает")
    func unknownLanguage() {
        let source = "func whatever() {}"
        #expect(SymbolNameExtractor.declarations(in: source, language: "markdown").isEmpty)
    }
}
