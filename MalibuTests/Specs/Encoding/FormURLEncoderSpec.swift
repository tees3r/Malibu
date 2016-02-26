@testable import Malibu
import Quick
import Nimble

class FormURLEncoderSpec: QuickSpec {
  
  override func spec() {
    describe("FormURLEncoder") {
      var encoder: FormURLEncoder!
      
      beforeEach {
        encoder = FormURLEncoder()
      }
      
      describe("#escapingCharacters") {
        it("should hold reserved characters") {
          expect(encoder.escapingCharacters).to(equal(":#[]@!$&'()*+,;="))
        }
      }
      
      describe("#encode") {
        it("encodes a dictionary of parameters to NSData object") {
          let parameters = ["firstname": "John", "lastname": "Hyperseed"]
          let string = encoder.queryString(parameters)
          let data = string.dataUsingEncoding(NSUTF8StringEncoding,
            allowLossyConversion: false)
          
          expect{ try encoder.encode(parameters) }.to(equal(data))
        }
      }
      
      describe("#queryString") {
        context("with empty dictionary") {
          it("builds encoded query string") {
            let parameters = [String: AnyObject]()
            expect(encoder.queryString(parameters)).to(equal(""))
          }
        }
        
        context("with one string parameter") {
          it("builds encoded query string") {
            let parameters = ["firstname": "Taylor"]
            let string = "firstname=Taylor"
            
            expect(encoder.queryString(parameters)).to(equal(string))
          }
        }
        
        context("with multiple string parameters") {
          it("builds encoded query string") {
            let parameters = ["firstname": "Taylor", "lastname": "Hyperseed", "sex": "female"]
            let string = "firstname=Taylor&lastname=Hyperseed&sex=female"
            
            expect(encoder.queryString(parameters)).to(equal(string))
          }
        }
        
        context("with integer parameter") {
          it("builds encoded query string") {
            let parameters = ["value": 11]
            let string = "value=11"
          
            expect(encoder.queryString(parameters)).to(equal(string))
          }
        }
        
        context("with double parameter") {
          it("builds encoded query string") {
            let parameters = ["value": 11.1]
            let string = "value=11.1"
          
            expect(encoder.queryString(parameters)).to(equal(string))
          }
        }
        
        context("with boolean parameter") {
          it("builds encoded query string") {
            let parameters = ["value": true]
            let string = "value=1"
          
            expect(encoder.queryString(parameters)).to(equal(string))
          }
        }
        
        context("with array parameter") {
          it("builds encoded query string") {
            let parameters = ["array": ["string", 11, true]]
            let string = "array%5B%5D=string&array%5B%5D=11&array%5B%5D=1"
          
            expect(encoder.queryString(parameters)).to(equal(string))
          }
        }
        
        context("with dictionary parameter") {
          it("builds encoded query string") {
            let parameters = ["dictionary": ["value": 12]]
            let string = "dictionary%5Bvalue%5D=12"
          
            expect(encoder.queryString(parameters)).to(equal(string))
          }
        }
        
        context("with nested dictionary parameter") {
          it("builds encoded query string") {
            let parameters = ["dictionary": ["nested": ["value": 7.1]]]
            let string = "dictionary%5Bnested%5D%5Bvalue%5D=7.1"
          
            expect(encoder.queryString(parameters)).to(equal(string))
          }
        }
        
        context("with nested dictionary and array") {
          it("builds encoded query string") {
            let parameters = ["dictionary": ["nested": ["key": ["value", 8, true]]]]
            let string = "dictionary%5Bnested%5D%5Bkey%5D%5B%5D=value&dictionary%5Bnested%5D%5Bkey%5D%5B%5D=8&dictionary%5Bnested%5D%5Bkey%5D%5B%5D=1"
          
            expect(encoder.queryString(parameters)).to(equal(string))
          }
        }
      }
      
      describe("#queryComponents") {
        it("builds a query component based on key and value") {
          let key = "firstname"
          let value = "Taylor"
          let components = encoder.queryComponents(key: key, value: value)
          
          expect(components[0].0).to(equal("firstname"))
          expect(components[0].1).to(equal("Taylor"))
        }
      }
      
      describe("#escape") {
        it("percent-escapes all reserved characters according to RFC 3986") {
          let string = encoder.escapingCharacters
          let result = "%3A%23%5B%5D%40%21%24%26%27%28%29%2A%2B%2C%3B%3D"
          
          expect(encoder.escape(string)).to(equal(result))
        }
        
        it("percent-escapes illegal ASCII characters") {
          let string = " \"#%<>[]\\^`{}|"
          let result = "%20%22%23%25%3C%3E%5B%5D%5C%5E%60%7B%7D%7C"
          
          expect(encoder.escape(string)).to(equal(result))
        }
        
        it("percent-escapes non-latin characters") {
          expect(encoder.escape("Børk Børk Børk!!")).to(equal("B%C3%B8rk%20B%C3%B8rk%20B%C3%B8rk%21%21"))
          expect(encoder.escape("українська мова")).to(equal("%D1%83%D0%BA%D1%80%D0%B0%D1%97%D0%BD%D1%81%D1%8C%D0%BA%D0%B0%20%D0%BC%D0%BE%D0%B2%D0%B0"))
          expect(encoder.escape("català")).to(equal("catal%C3%A0"))
          expect(encoder.escape("Tiếng Việt")).to(equal("Ti%E1%BA%BFng%20Vi%E1%BB%87t"))
          expect(encoder.escape("日本の")).to(equal("%E6%97%A5%E6%9C%AC%E3%81%AE"))
          expect(encoder.escape("العربية")).to(equal("%D8%A7%D9%84%D8%B9%D8%B1%D8%A8%D9%8A%D8%A9"))
          expect(encoder.escape("或許谷歌翻譯會給一些隨機的翻譯，現在")).to(equal("%E6%88%96%E8%A8%B1%E8%B0%B7%E6%AD%8C%E7%BF%BB%E8%AD%AF%E6%9C%83%E7%B5%A6%E4%B8%80%E4%BA%9B%E9%9A%A8%E6%A9%9F%E7%9A%84%E7%BF%BB%E8%AD%AF%EF%BC%8C%E7%8F%BE%E5%9C%A8"))
          expect(encoder.escape("😃")).to(equal("%F0%9F%98%83"))
        }
        
        it("does not percent-escape reserved characters ? and /") {
          let string = "?/"
          
          expect(encoder.escape(string)).to(equal(string))
        }
        
        it("does not percent-escape unreserved characters") {
          let string = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
          
          expect(encoder.escape(string)).to(equal(string))
        }
      }
    }
  }
}
