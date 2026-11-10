import Foundation

// MARK: - ERRORES
enum FormulaError: Error, Equatable, LocalizedError {
    case emptyExpression
    case unexpectedCharacter(Character)
    case unknownVariable(String)
    case unknownFunction(String)
    case pendingGrade(String)
    case emptyArguments(String)
    case missingParenthesis
    case unbalancedParenthesis
    case divisionByZero
    case invalidResult
    case syntax

    var errorDescription: String? {
        switch self {
        case .emptyExpression:
            return "Escribe una fórmula."
        case .unexpectedCharacter(let c):
            return "Carácter no válido: «\(c)». Los decimales se escriben con punto (0.6)."
        case .unknownVariable(let name):
            return "«\(name)» no existe. Usa Media o el nombre de una evaluación."
        case .unknownFunction(let name):
            return "Función «\(name)» desconocida. Puedes usar min y max."
        case .pendingGrade(let name):
            return "«\(name)» aún no tiene nota. Ponla o activa «Tratar pendientes como 0»."
        case .emptyArguments(let name):
            return "«\(name)» necesita al menos un valor."
        case .missingParenthesis:
            return "Falta cerrar un paréntesis."
        case .unbalancedParenthesis:
            return "Hay un paréntesis de cierre de más."
        case .divisionByZero:
            return "División entre cero."
        case .invalidResult:
            return "El resultado no es un número válido."
        case .syntax:
            return "La expresión está incompleta o mal escrita."
        }
    }
}

// MARK: - VARIABLES DISPONIBLES
/// Valores que se pueden usar dentro de la fórmula (Media, nombres de evaluaciones…).
/// Un valor `nil` significa "evaluación sin nota todavía".
struct FormulaVariables {
    private(set) var values: [String: Double] = [:]
    private(set) var pending: Set<String> = []

    /// La primera definición de un nombre gana (así "Media" no se puede pisar).
    mutating func set(_ name: String, value: Double?) {
        let key = FormulaEvaluator.normalize(name)
        guard !key.isEmpty, values[key] == nil, !pending.contains(key) else { return }
        if let value {
            values[key] = value
        } else {
            pending.insert(key)
        }
    }
}

// MARK: - EVALUADOR
enum FormulaEvaluator {

    /// Calcula la expresión. Soporta + - * / ^, paréntesis, variables,
    /// y las funciones min(...) y max(...) con cualquier número de valores.
    static func evaluate(_ expression: String, variables: FormulaVariables) -> Result<Double, FormulaError> {
        do {
            let tokens = try tokenize(expression)
            guard !tokens.isEmpty else { throw FormulaError.emptyExpression }

            var parser = Parser(tokens: tokens, variables: variables)
            let value = try parser.parseExpression()

            if let leftover = parser.current {
                throw leftover == .rightParen ? FormulaError.unbalancedParenthesis : FormulaError.syntax
            }
            guard value.isFinite else { throw FormulaError.invalidResult }
            return .success(value)
        } catch let error as FormulaError {
            return .failure(error)
        } catch {
            return .failure(.syntax)
        }
    }

    /// Clave interna de un nombre: sin tildes, mayúsculas, espacios ni símbolos.
    /// "Prueba Final" y "pruebafinal" son la misma variable.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Cómo escribir el nombre de una evaluación dentro de la fórmula.
    static func identifier(for name: String) -> String {
        name.filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    // MARK: Tokenizador
    private static func isDigit(_ c: Character) -> Bool {
        ("0"..."9").contains(c)
    }

    private static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || isDigit(c) || c == "_"
    }

    private static func tokenize(_ text: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(text)
        var i = 0

        while i < chars.count {
            let c = chars[i]

            if c.isWhitespace {
                i += 1
                continue
            }

            // Número o identificador
            if isWordCharacter(c) {
                var j = i
                while j < chars.count, isWordCharacter(chars[j]) { j += 1 }
                let run = String(chars[i..<j])

                if run.allSatisfy(isDigit) {
                    var literal = run
                    if j + 1 < chars.count, chars[j] == ".", isDigit(chars[j + 1]) {
                        j += 1
                        let start = j
                        while j < chars.count, isDigit(chars[j]) { j += 1 }
                        literal += "." + String(chars[start..<j])
                    }
                    guard let value = Double(literal) else { throw FormulaError.unexpectedCharacter(c) }
                    tokens.append(.number(value))
                } else {
                    tokens.append(.identifier(run))
                }
                i = j
                continue
            }

            // Número que empieza por punto (.5)
            if c == ".", i + 1 < chars.count, isDigit(chars[i + 1]) {
                var j = i + 1
                while j < chars.count, isDigit(chars[j]) { j += 1 }
                guard let value = Double("0" + String(chars[i..<j])) else { throw FormulaError.unexpectedCharacter(c) }
                tokens.append(.number(value))
                i = j
                continue
            }

            switch c {
            case "+": tokens.append(.plus)
            case "-", "−", "–": tokens.append(.minus)
            case "*", "×", "·": tokens.append(.star)
            case "/", "÷": tokens.append(.slash)
            case "^": tokens.append(.caret)
            case "(": tokens.append(.leftParen)
            case ")": tokens.append(.rightParen)
            case ",", ";": tokens.append(.comma)
            default: throw FormulaError.unexpectedCharacter(c)
            }
            i += 1
        }
        return tokens
    }
}

// MARK: - TOKENS Y PARSER
private enum Token: Equatable {
    case number(Double)
    case identifier(String)
    case plus, minus, star, slash, caret
    case leftParen, rightParen, comma
}

/// Precedencia: paréntesis > potencia > signo unario > * / > + -
private struct Parser {
    let tokens: [Token]
    let variables: FormulaVariables
    var position = 0

    var current: Token? { position < tokens.count ? tokens[position] : nil }

    mutating func advance() { position += 1 }

    // expresión := término (('+' | '-') término)*
    mutating func parseExpression() throws -> Double {
        var value = try parseTerm()
        while let token = current, token == .plus || token == .minus {
            advance()
            let rhs = try parseTerm()
            value = (token == .plus) ? value + rhs : value - rhs
        }
        return value
    }

    // término := unario (('*' | '/') unario)*
    mutating func parseTerm() throws -> Double {
        var value = try parseUnary()
        while let token = current, token == .star || token == .slash {
            advance()
            let rhs = try parseUnary()
            if token == .slash {
                guard rhs != 0 else { throw FormulaError.divisionByZero }
                value /= rhs
            } else {
                value *= rhs
            }
        }
        return value
    }

    // unario := ('-' | '+') unario | potencia
    mutating func parseUnary() throws -> Double {
        if let token = current, token == .minus {
            advance()
            return -(try parseUnary())
        }
        if let token = current, token == .plus {
            advance()
            return try parseUnary()
        }
        return try parsePower()
    }

    // potencia := primario ('^' unario)?
    mutating func parsePower() throws -> Double {
        let base = try parsePrimary()
        if let token = current, token == .caret {
            advance()
            let exponent = try parseUnary()
            return pow(base, exponent)
        }
        return base
    }

    // primario := número | variable | función '(' args ')' | '(' expresión ')'
    mutating func parsePrimary() throws -> Double {
        guard let token = current else { throw FormulaError.syntax }

        switch token {
        case .number(let value):
            advance()
            return value

        case .identifier(let name):
            advance()
            if let next = current, next == .leftParen {
                return try parseFunction(name)
            }
            return try variable(named: name)

        case .leftParen:
            advance()
            let value = try parseExpression()
            guard let closing = current, closing == .rightParen else { throw FormulaError.missingParenthesis }
            advance()
            return value

        default:
            throw FormulaError.syntax
        }
    }

    private func variable(named name: String) throws -> Double {
        let key = FormulaEvaluator.normalize(name)
        if let value = variables.values[key] { return value }
        if variables.pending.contains(key) { throw FormulaError.pendingGrade(name) }
        throw FormulaError.unknownVariable(name)
    }

    /// min(a, b, c, …) devuelve el menor; max(a, b, c, …) devuelve el mayor.
    private mutating func parseFunction(_ name: String) throws -> Double {
        let key = FormulaEvaluator.normalize(name)
        let isMin = (key == "min" || key == "minimo")
        let isMax = (key == "max" || key == "maximo")
        guard isMin || isMax else { throw FormulaError.unknownFunction(name) }

        advance() // consume '('
        if let token = current, token == .rightParen {
            throw FormulaError.emptyArguments(name)
        }

        var arguments: [Double] = []
        while true {
            arguments.append(try parseExpression())

            if let token = current, token == .comma {
                advance()
                continue
            }
            if let token = current, token == .rightParen {
                advance()
                break
            }
            throw FormulaError.missingParenthesis
        }

        let result = isMin ? arguments.min() : arguments.max()
        return result ?? 0
    }
}
